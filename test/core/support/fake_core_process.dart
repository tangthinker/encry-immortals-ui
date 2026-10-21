import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encry_immortals_ui/core/core_process.dart';

class FakeCoreProcess implements CoreProcess {
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  final BytesBuilder stdinBytes = BytesBuilder(copy: false);

  bool stdinClosed = false;
  bool killed = false;
  ProcessSignal? lastSignal;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  void write(List<int> bytes) => stdinBytes.add(bytes);

  @override
  Future<void> closeStdin() async {
    stdinClosed = true;
  }

  void emitStdout(String text) {
    if (!_stdout.isClosed) _stdout.add(utf8.encode(text));
  }

  void emitStderrLine(String line) {
    if (!_stderr.isClosed) _stderr.add(utf8.encode('$line\n'));
  }

  Future<void> finish(int code) async {
    if (!_stdout.isClosed) unawaited(_stdout.close());
    if (!_stderr.isClosed) unawaited(_stderr.close());
    if (!_exitCode.isCompleted) _exitCode.complete(code);
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    lastSignal = signal;
    unawaited(finish(130));
    return true;
  }
}

class FakeLaunchCall {
  FakeLaunchCall({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
}

class FakeCoreLauncher implements CoreProcessLauncher {
  FakeCoreLauncher(this.process);

  final FakeCoreProcess process;
  final List<FakeLaunchCall> calls = <FakeLaunchCall>[];
  final Completer<void> launched = Completer<void>();

  @override
  Future<CoreProcess> launch(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls.add(
      FakeLaunchCall(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      ),
    );
    if (!launched.isCompleted) launched.complete();
    return process;
  }
}
