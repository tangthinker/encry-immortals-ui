import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'app_paths.dart';
import 'command_queue.dart';
import 'core_command.dart';
import 'core_exit_code.dart';
import 'core_gateway.dart';
import 'core_models.dart';
import 'core_result.dart';
import 'profile.dart';
import 'profile_store.dart';
import 'vault_session.dart';

class OnboardingValidationException implements Exception {
  const OnboardingValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OnboardingStepResult {
  const OnboardingStepResult({
    required this.label,
    required this.ok,
    required this.detail,
    required this.duration,
  });

  final String label;
  final bool ok;
  final String detail;
  final Duration duration;
}

class OnboardingResult {
  const OnboardingResult({
    required this.success,
    required this.steps,
    this.cancelled = false,
    this.profile,
    this.key,
    this.error,
    this.exitCode,
    this.vaultCreated = false,
  });

  final bool success;
  final bool cancelled;
  final List<OnboardingStepResult> steps;
  final Profile? profile;
  final ExportKeyInfo? key;
  final String? error;
  final CoreExitCode? exitCode;

  /// 本地控制平面是否曾被创建（失败后服务会清理；用于 UI 提示）。
  final bool vaultCreated;
}

typedef OnboardingLog = void Function(String message);
typedef OnboardingStepListener = void Function(OnboardingStepResult step);

/// 创建/加入库。只写应用数据目录和用户选择的 TargetDir；失败会清理本地控制平面，
/// 绝不删除 TargetDir 里的任何数据。
class OnboardingService {
  OnboardingService({
    required this.gateway,
    required this.paths,
    required this.store,
    required this.queue,
  });

  final CoreGateway gateway;
  final AppPaths paths;
  final ProfileStore store;
  final CommandQueue queue;

  Profile? _profile;
  bool _vaultCreated = false;
  bool _configWritten = false;
  final List<OnboardingStepResult> _steps = [];

  Future<OnboardingResult> create({
    required String sourceRoot,
    required String targetDir,
    required String password,
    OnboardingLog? onLog,
    OnboardingStepListener? onStep,
  }) async {
    _resetLocalState();
    try {
      await _validateCreate(sourceRoot, targetDir, password);
      final profile = await _prepareProfile(
        sourceRoot: sourceRoot,
        targetDir: targetDir,
        mode: ProfileMode.created,
      );

      final configStep = await _record(
        '准备配置',
        () async {
          await store.writeConfig(profile);
          _configWritten = true;
          return 'config.toml 已写入（0600）';
        },
        onStep: onStep,
        onLog: onLog,
      );
      if (!configStep) return await _failure();

      final initStep = await _record(
        '初始化加密库',
        () async {
          final result = await _run(
            CoreCommand.init,
            configPath: profile.configPath,
            password: password,
            onLog: onLog,
          );
          if (result.cancelled) return _cancel();
          if (!result.isSuccess) {
            throw _CoreStepFailure(result);
          }
          _vaultCreated = true;
          return 'KDF 与 vault.meta 已生成';
        },
        onStep: onStep,
        onLog: onLog,
      );
      if (!initStep) return await _failure();

      final keyStep = await _record(
        '导出 Armor Key',
        () async {
          final result = await _run(
            CoreCommand.exportKey,
            configPath: profile.configPath,
            onLog: onLog,
          );
          if (result.cancelled) return _cancel();
          final info = exportKeyFromResult(result);
          if (!result.isSuccess || info == null) {
            throw _CoreStepFailure(result, '无法解析 export-key --json');
          }
          _key = info;
          return '已捕获，仅保存在内存';
        },
        onStep: onStep,
        onLog: onLog,
      );
      if (!keyStep) return await _failure();

      final saveStep = await _record(
        '保存 profile',
        () async {
          await store.save(profile);
          return '源根目录已固定：${profile.sourceRoot}';
        },
        onStep: onStep,
        onLog: onLog,
      );
      if (!saveStep) return await _failure();

      _profile = profile;
      _vaultCreated = false;
      return _success();
    } catch (error) {
      return await _failure(error);
    }
  }

  Future<OnboardingResult> join({
    required String sourceRoot,
    required String targetDir,
    required String armorKey,
    required String password,
    OnboardingLog? onLog,
    OnboardingStepListener? onStep,
  }) async {
    _resetLocalState();
    try {
      await _validateJoin(sourceRoot, targetDir, armorKey, password);
      final profile = await _prepareProfile(
        sourceRoot: sourceRoot,
        targetDir: targetDir,
        mode: ProfileMode.joined,
      );

      final configStep = await _record(
        '准备配置',
        () async {
          await store.writeConfig(profile);
          _configWritten = true;
          return 'config.toml 已写入（0600）';
        },
        onStep: onStep,
        onLog: onLog,
      );
      if (!configStep) return await _failure();

      final joinStep = await _record(
        '登记 TargetDir',
        () async {
          final result = await _run(
            CoreCommand.initJoin,
            args: ['--join', targetDir],
            configPath: profile.configPath,
            onLog: onLog,
          );
          if (result.cancelled) return _cancel();
          if (!result.isSuccess) throw _CoreStepFailure(result);
          _vaultCreated = true;
          return 'pending-target 已登记';
        },
        onStep: onStep,
        onLog: onLog,
      );
      if (!joinStep) return await _failure();

      final importStep = await _record(
        '导入 Armor Key',
        () async {
          final result = await _run(
            CoreCommand.importKey,
            configPath: profile.configPath,
            armorKey: armorKey,
            onLog: onLog,
          );
          if (result.cancelled) return _cancel();
          if (!result.isSuccess) throw _CoreStepFailure(result);
          return 'vault.meta 已导入';
        },
        onStep: onStep,
        onLog: onLog,
      );
      if (!importStep) return await _failure();

      final unlockStep = await _record(
        '验证主密码',
        () async {
          final result = await _run(
            CoreCommand.log,
            configPath: profile.configPath,
            password: password,
            onLog: onLog,
          );
          if (result.cancelled) return _cancel();
          if (!result.isSuccess || result.jsonList == null) {
            throw _CoreStepFailure(result, '密码错误或历史无法解析');
          }
          return '解锁成功，历史可读';
        },
        onStep: onStep,
        onLog: onLog,
      );
      if (!unlockStep) return await _failure();

      final doctorStep = await _record(
        '校验数据链',
        () async {
          final result = await _run(
            CoreCommand.doctor,
            args: ['--chain'],
            configPath: profile.configPath,
            password: password,
            onLog: onLog,
          );
          if (result.cancelled) return _cancel();
          final checks = result.jsonList
              ?.map((item) => DoctorCheck.fromJson(asJsonMap(item)))
              .toList();
          if (!result.isSuccess ||
              checks == null ||
              checks.any((check) => check.status.isBlocking)) {
            throw _CoreStepFailure(result, 'doctor --chain 未通过');
          }
          return '${checks.length} 项检查通过';
        },
        onStep: onStep,
        onLog: onLog,
      );
      if (!doctorStep) return await _failure();

      final saveStep = await _record(
        '保存 profile',
        () async {
          await store.save(profile);
          return '源根目录已固定：${profile.sourceRoot}';
        },
        onStep: onStep,
        onLog: onLog,
      );
      if (!saveStep) return await _failure();

      _profile = profile;
      _vaultCreated = false;
      return _success();
    } catch (error) {
      return await _failure(error);
    }
  }

  ExportKeyInfo? _key;

  Future<Profile> _prepareProfile({
    required String sourceRoot,
    required String targetDir,
    required ProfileMode mode,
  }) async {
    final id = _newId();
    final profile = Profile(
      id: id,
      name: p.basename(p.normalize(targetDir)) == ''
          ? '加密备份库'
          : p.basename(p.normalize(targetDir)),
      vaultDir: paths.vaultDir,
      targetDir: targetDir,
      configPath: paths.configFile,
      sourceRoot: sourceRoot,
      mode: mode,
      createdAt: DateTime.now(),
      sessionMaxMib: 1024,
      ignoreXattr: Platform.isMacOS,
    );
    return profile;
  }

  Future<void> _validateCreate(
    String sourceRoot,
    String targetDir,
    String password,
  ) async {
    _validatePassword(password);
    await _validateDirs(sourceRoot, targetDir);
    final source = p.canonicalize(sourceRoot);
    final target = p.canonicalize(targetDir);
    if (p.equals(source, target) ||
        p.isWithin(source, target) ||
        p.isWithin(target, source)) {
      throw const OnboardingValidationException('源目录与 TargetDir 不能相同或互相包含。');
    }
    final entries = Directory(target)
        .listSync()
        .where((entry) => p.basename(entry.path) != '.DS_Store')
        .toList();
    if (entries.isNotEmpty) {
      throw const OnboardingValidationException(
        '新建库要求 TargetDir 为空；如要使用已有备份，请选择“加入已有库”。',
      );
    }
    await _ensureVaultAvailable();
  }

  Future<void> _validateJoin(
    String sourceRoot,
    String targetDir,
    String armorKey,
    String password,
  ) async {
    _validatePassword(password);
    await _validateDirs(sourceRoot, targetDir);
    final source = p.canonicalize(sourceRoot);
    final target = p.canonicalize(targetDir);
    if (p.equals(source, target) ||
        p.isWithin(source, target) ||
        p.isWithin(target, source)) {
      throw const OnboardingValidationException('源目录与 TargetDir 不能相同或互相包含。');
    }
    final hasData =
        Directory(p.join(targetDir, 'meta')).existsSync() ||
        Directory(p.join(targetDir, 'data')).existsSync();
    if (!hasData) {
      throw const OnboardingValidationException(
        'TargetDir 里没有 meta/ 或 data/，不像是 eimmortal 备份目录。',
      );
    }
    final normalized = armorKey.replaceAll(RegExp(r'\s'), '');
    if (!normalized.startsWith('EIMMORTAL-KEY-V2-')) {
      throw const OnboardingValidationException(
        'Armor Key 格式不正确，应以 EIMMORTAL-KEY-V2- 开头。',
      );
    }
    await _ensureVaultAvailable();
  }

  void _validatePassword(String password) {
    if (password.contains('\n') || password.contains('\r')) {
      throw const OnboardingValidationException('主密码不能包含换行。');
    }
    if (utf8.encode(password).length < 12) {
      throw const OnboardingValidationException('主密码至少需要 12 个字节（推荐 4 个以上随机单词）。');
    }
  }

  Future<void> _validateDirs(String sourceRoot, String targetDir) async {
    final source = Directory(sourceRoot);
    final target = Directory(targetDir);
    if (!await source.exists()) {
      throw const OnboardingValidationException('源目录不存在。');
    }
    if (!await target.exists()) {
      throw const OnboardingValidationException('TargetDir 不存在。');
    }
    try {
      await source.list().take(1).toList();
    } on FileSystemException catch (error) {
      throw OnboardingValidationException('无法读取源目录：$error');
    }
    try {
      await target.list().take(1).toList();
    } on FileSystemException catch (error) {
      throw OnboardingValidationException('无法读取 TargetDir：$error');
    }
  }

  Future<void> _ensureVaultAvailable() async {
    if (await File(paths.profileFile).exists()) {
      throw const OnboardingValidationException('应用配置已存在，不能重复初始化。');
    }
    if (await File(p.join(paths.vaultDir, 'vault.meta')).exists()) {
      throw const OnboardingValidationException(
        '本地控制平面已存在 vault.meta。请先重置本地配置，或继续使用现有 profile。',
      );
    }
  }

  Future<bool> _record(
    String label,
    Future<String> Function() action, {
    OnboardingStepListener? onStep,
    OnboardingLog? onLog,
  }) async {
    final stopwatch = Stopwatch()..start();
    _lastFailure = null;
    _lastError = null;
    onLog?.call('▶ $label');
    try {
      final detail = await action();
      stopwatch.stop();
      final step = OnboardingStepResult(
        label: label,
        ok: true,
        detail: detail,
        duration: stopwatch.elapsed,
      );
      _steps.add(step);
      onStep?.call(step);
      onLog?.call('✓ $label · $detail');
      return true;
    } on _Cancelled {
      stopwatch.stop();
      final step = OnboardingStepResult(
        label: label,
        ok: false,
        detail: '已取消',
        duration: stopwatch.elapsed,
      );
      _steps.add(step);
      onStep?.call(step);
      onLog?.call('■ $label · 已取消');
      rethrow;
    } on _CoreStepFailure catch (failure) {
      stopwatch.stop();
      final step = OnboardingStepResult(
        label: label,
        ok: false,
        detail: failure.message,
        duration: stopwatch.elapsed,
      );
      _steps.add(step);
      onStep?.call(step);
      _lastFailure = failure;
      onLog?.call('✗ $label · ${failure.message}');
      return false;
    } catch (error) {
      stopwatch.stop();
      final step = OnboardingStepResult(
        label: label,
        ok: false,
        detail: '$error',
        duration: stopwatch.elapsed,
      );
      _steps.add(step);
      onStep?.call(step);
      _lastError = error;
      onLog?.call('✗ $label · $error');
      return false;
    }
  }

  _CoreStepFailure? _lastFailure;
  Object? _lastError;
  bool _cancelled = false;

  Future<CoreResult> _run(
    CoreCommand command, {
    List<String> args = const [],
    required String configPath,
    String? password,
    String? armorKey,
    OnboardingLog? onLog,
  }) {
    return queue.run(command.label, (ticket) async {
      final run = gateway.start(
        CoreRequest(
          command: command,
          args: args,
          password: password,
          armorKey: armorKey,
          configPath: configPath,
        ),
      );
      ticket.attach(run.cancel);
      final subscription = onLog == null
          ? null
          : run.stderrLines.listen((line) {
              // 只转发命令/进度的安全摘要；stdout 从不进入日志。
              onLog('[${command.name}] $line');
            });
      try {
        final result = await run.result;
        if (result.cancelled) _cancelled = true;
        return result;
      } finally {
        await subscription?.cancel();
      }
    });
  }

  OnboardingResult _success() {
    return OnboardingResult(
      success: true,
      steps: List<OnboardingStepResult>.unmodifiable(_steps),
      profile: _profile,
      key: _key,
    );
  }

  Future<OnboardingResult> _failure([Object? error]) async {
    final failure = _lastFailure;
    final cancelled = _cancelled;
    final message = cancelled
        ? '操作已取消，本地控制平面已清理；TargetDir 未改动。'
        : failure?.message ??
              _lastError?.toString() ??
              error?.toString() ??
              '初始化失败。';
    final exitCode = failure?.result.exit;
    final vaultCreated = _vaultCreated;
    if (_configWritten || _vaultCreated) {
      // 只清理本次尝试写下的本地配置；_vaultCreated 为 true 时才删控制平面。
      await _cleanupLocalVault();
    }
    return OnboardingResult(
      success: false,
      cancelled: cancelled,
      steps: List<OnboardingStepResult>.unmodifiable(_steps),
      error: message,
      exitCode: exitCode,
      vaultCreated: vaultCreated,
    );
  }

  Future<void> _cleanupLocalVault() async {
    try {
      await store.forget(deleteVault: _vaultCreated);
    } catch (_) {
      // 清理失败不应遮蔽原始错误；UI 会显示“重置本地配置”。
    }
  }

  void _resetLocalState() {
    _steps.clear();
    _profile = null;
    _key = null;
    _lastFailure = null;
    _lastError = null;
    _cancelled = false;
    _vaultCreated = false;
    _configWritten = false;
  }

  String _newId() {
    final random = Random.secure();
    final suffix = List<String>.generate(
      8,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}-$suffix';
  }
}

class _Cancelled implements Exception {}

class _CoreStepFailure implements Exception {
  _CoreStepFailure(this.result, [String? detail])
    : message = detail ?? _summarize(result);

  final CoreResult result;
  final String message;

  static String _summarize(CoreResult result) {
    final summary = result.errorSummary;
    return 'exit ${result.exitCode} · ${result.exit.guidance} ${summary == result.exit.label ? '' : summary}'
        .trim();
  }
}

Never _cancel() => throw _Cancelled();
