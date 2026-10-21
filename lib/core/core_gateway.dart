import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'core_command.dart';
import 'core_locator.dart';
import 'core_process.dart';
import 'core_result.dart';

/// 一次 sidecar 调用的参数。密码只存在于内存与 stdin 管道。
class CoreRequest {
  const CoreRequest({
    required this.command,
    this.args = const [],
    this.password,
    this.armorKey,
    this.configPath,
    this.vaultPath,
    this.timeout,
    this.workingDirectory,
    this.label,
  });

  final CoreCommand command;
  final List<String> args;

  /// 主密码；是否真正写入 stdin 由 [CoreCommand.needsPasswordFor] 决定。
  final String? password;

  /// `import-key` 的 Armor Key（只走 stdin，不写 argv）。
  final String? armorKey;

  final String? configPath;
  final String? vaultPath;
  final Duration? timeout;
  final String? workingDirectory;

  /// 进度面板展示的动作名；默认用 [CoreCommand.label]。
  final String? label;

  CoreStdin get effectiveStdin {
    if (command.stdin == CoreStdin.armorKey) {
      return armorKey == null ? CoreStdin.none : CoreStdin.armorKey;
    }
    if (password != null && password!.isNotEmpty &&
        command.needsPasswordFor(args)) {
      return CoreStdin.password;
    }
    return CoreStdin.none;
  }

  String? get stdinPayload {
    switch (effectiveStdin) {
      case CoreStdin.password:
        return '${password!}\n';
      case CoreStdin.armorKey:
        return '${armorKey!.trim()}\n';
      case CoreStdin.none:
        return null;
    }
  }
}

/// 一个已经启动的 sidecar 调用。取消通过 [cancel] 触发。
class CoreRun {
  const CoreRun({
    required this.command,
    required this.result,
    required this.cancel,
    required this.stderrLines,
  });

  final CoreCommand command;
  final Future<CoreResult> result;
  final Future<void> Function() cancel;
  final Stream<String> stderrLines;
}

class CoreLaunchException implements Exception {
  const CoreLaunchException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message（$cause）';
}

/// sidecar 网关：构造参数、写 stdin、并发读 stdout/stderr、解析 JSON、映射退出码。
class CoreGateway {
  CoreGateway({
    required this.binary,
    this.launcher = const SystemCoreProcessLauncher(),
    this.defaultTimeout,
  });

  final CoreBinary binary;
  final CoreProcessLauncher launcher;
  final Duration? defaultTimeout;

  /// 供单元测试和诊断使用：密码永远不会出现在 argv 中。
  List<String> buildArguments(CoreRequest request) {
    final args = <String>[];
    if (request.configPath != null) {
      args
        ..add('--config')
        ..add(request.configPath!);
    }
    if (request.command.supportsJson) args.add('--json');
    if (request.vaultPath != null) {
      args
        ..add('--vault')
        ..add(request.vaultPath!);
    }
    if (request.effectiveStdin == CoreStdin.password) {
      args
        ..add('--password-fd')
        ..add('0');
    }
    args.add(request.command.name);
    args.addAll(request.args);
    return args;
  }

  CoreRun start(CoreRequest request) {
    _validate(request);
    final execution = _CoreExecution(this, request);
    return execution.start();
  }

  Future<CoreResult> run(CoreRequest request) => start(request).result;

  void _validate(CoreRequest request) {
    final password = request.password;
    if (password != null && (password.contains('\n') || password.contains('\r'))) {
      throw ArgumentError('主密码不能包含换行；CLI 按行读取 stdin。');
    }
    if (request.command == CoreCommand.init &&
        (password == null || password.isEmpty)) {
      throw ArgumentError('init 必须提供非空主密码。');
    }
    if (request.command == CoreCommand.importKey &&
        (request.armorKey == null || request.armorKey!.trim().isEmpty)) {
      throw ArgumentError('import-key 必须通过 stdin 提供 Armor Key。');
    }
  }
}

class _CoreExecution {
  _CoreExecution(this.gateway, this.request);

  final CoreGateway gateway;
  final CoreRequest request;

  final Completer<CoreResult> _completer = Completer<CoreResult>();
  final StreamController<String> _stderrController =
      StreamController<String>.broadcast();
  final StringBuffer _stderrBuffer = StringBuffer();
  final BytesBuilder _stdoutBuilder = BytesBuilder(copy: false);

  CoreProcess? _process;
  Timer? _killTimer;
  bool _cancelled = false;
  bool _timedOut = false;
  bool _finished = false;
  bool _stdoutTruncated = false;
  int _stderrBytes = 0;

  static const int _stdoutLimit = 16 * 1024 * 1024;
  static const int _stderrLimit = 256 * 1024;

  CoreRun start() {
    unawaited(_run());
    return CoreRun(
      command: request.command,
      result: _completer.future,
      cancel: cancel,
      stderrLines: _stderrController.stream,
    );
  }

  Future<void> cancel() async {
    if (_finished) return;
    _cancelled = true;
    _terminate();
  }

  void _terminate() {
    final process = _process;
    if (process == null) return;
    process.kill(ProcessSignal.sigterm);
    _killTimer?.cancel();
    _killTimer = Timer(const Duration(seconds: 5), () {
      if (!_finished) process.kill(ProcessSignal.sigkill);
    });
  }

  Future<void> _run() async {
    final stopwatch = Stopwatch()..start();
    final startedAt = DateTime.now();
    final arguments = gateway.buildArguments(request);
    var exitCode = -1;
    var stdout = '';
    var stderr = '';

    try {
      if (!gateway.binary.exists()) {
        throw CoreLaunchException(
          'sidecar 不存在：${gateway.binary.path}',
        );
      }

      final process = await gateway.launcher.launch(
        gateway.binary.path,
        arguments,
        workingDirectory:
            request.workingDirectory ?? defaultCoreWorkingDirectory(),
        environment: buildCoreEnvironment(),
      );
      _process = process;
      if (_cancelled) _terminate();

      final stdoutFuture = _collectStdout(process.stdout);
      final stderrFuture = _collectStderr(process.stderr);

      final payload = request.stdinPayload;
      if (payload != null) {
        process.write(utf8.encode(payload));
      }
      await process.closeStdin();

      final timeout = request.timeout ?? gateway.defaultTimeout;
      Timer? timer;
      if (timeout != null) {
        timer = Timer(timeout, () {
          if (_finished) return;
          _timedOut = true;
          _terminate();
        });
      }

      try {
        exitCode = await process.exitCode;
      } finally {
        timer?.cancel();
      }

      final stdoutBytes = await stdoutFuture;
      await stderrFuture;

      stdout = utf8.decode(stdoutBytes, allowMalformed: true);
      stderr = _stderrBuffer.toString();
    } on CoreLaunchException catch (error) {
      _completer.completeError(error);
      _finished = true;
      await _finish();
      return;
    } catch (error, stackTrace) {
      stderr = '启动 sidecar 失败：$error';
      _completer.completeError(
        CoreLaunchException('无法执行 ${gateway.binary.path}', error),
        stackTrace,
      );
      _finished = true;
      await _finish();
      return;
    }

    final parsed = _parseJson(stdout, exitCode);
    final result = CoreResult(
      command: request.command,
      arguments: arguments,
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      json: parsed.value,
      jsonParsed: parsed.parsed,
      duration: stopwatch.elapsed,
      startedAt: startedAt,
      cancelled: _cancelled || exitCode == 130,
      timedOut: _timedOut,
      protocolError: parsed.protocolError,
      stdoutTruncated: _stdoutTruncated,
    );

    _finished = true;
    if (!_completer.isCompleted) _completer.complete(result);
    await _finish();
  }

  Future<void> _finish() async {
    _killTimer?.cancel();
    if (!_stderrController.isClosed) await _stderrController.close();
  }

  ({Object? value, bool parsed, bool protocolError}) _parseJson(
    String stdout,
    int exitCode,
  ) {
    if (!request.command.supportsJson) {
      return (value: null, parsed: false, protocolError: false);
    }
    final trimmed = stdout.trim();
    if (trimmed.isEmpty) {
      return (
        value: null,
        parsed: false,
        // 成功但没有任何 JSON：契约漂移。
        protocolError: exitCode == 0,
      );
    }
    try {
      return (
        value: jsonDecode(trimmed),
        parsed: true,
        protocolError: false,
      );
    } on FormatException {
      return (
        value: null,
        parsed: false,
        // 非零退出的命令可能把错误写 stdout；只有成功时才是协议问题。
        protocolError: exitCode == 0,
      );
    }
  }

  Future<List<int>> _collectStdout(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      final remaining = _stdoutLimit - _stdoutBuilder.length;
      if (remaining > 0) {
        if (chunk.length <= remaining) {
          _stdoutBuilder.add(chunk);
        } else {
          _stdoutBuilder.add(chunk.sublist(0, remaining));
          _stdoutTruncated = true;
        }
      } else {
        _stdoutTruncated = true;
      }
    }
    return _stdoutBuilder.takeBytes();
  }

  Future<void> _collectStderr(Stream<List<int>> stream) async {
    final done = Completer<void>();
    stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            _stderrBytes += line.length;
            if (_stderrBytes <= _stderrLimit) {
              if (_stderrBuffer.isNotEmpty) _stderrBuffer.write('\n');
              _stderrBuffer.write(line);
            }
            if (!_stderrController.isClosed) _stderrController.add(line);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!_stderrController.isClosed) {
              _stderrController.addError(error, stackTrace);
            }
          },
          onDone: done.complete,
          cancelOnError: false,
        );
    await done.future;
  }
}
