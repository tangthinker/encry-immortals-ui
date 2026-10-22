import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_paths.dart';
import '../core/command_queue.dart';
import '../core/core_exit_code.dart';
import '../core/core_models.dart';
import '../core/core_result.dart';
import '../core/core_runtime.dart';
import '../core/core_locator.dart';
import '../core/instance_lock.dart';
import '../core/lock_inspector.dart';
import '../core/onboarding_service.dart';
import '../core/platform_service.dart';
import '../core/profile.dart';
import '../core/profile_store.dart';
import '../core/vault_session.dart';
import '../core/vault_settings.dart';

enum AppPhase { starting, alreadyRunning, failed, onboarding, locked, unlocked }

class UnlockOutcome {
  const UnlockOutcome({required this.success, this.result, this.message});

  final bool success;
  final CoreResult? result;
  final String? message;
}

class AppController extends ChangeNotifier {
  AppController({
    required this.paths,
    required this.profileStore,
    CommandQueue? queue,
    CoreRuntimeLoader? runtimeLoader,
    this.platform = const PlatformService(),
    bool acquireInstanceLock = true,
    bool allowEnvironmentOverride = kDebugMode,
  }) : queue = queue ?? CommandQueue(),
       // ignore: prefer_initializing_formals
       _runtimeLoader = runtimeLoader,
       // ignore: prefer_initializing_formals
       _acquireInstanceLock = acquireInstanceLock,
       // ignore: prefer_initializing_formals
       _allowEnvironmentOverride = allowEnvironmentOverride;

  final AppPaths paths;
  final ProfileStore profileStore;
  final CommandQueue queue;
  final PlatformService platform;

  final CoreRuntimeLoader? _runtimeLoader;
  final bool _acquireInstanceLock;
  final bool _allowEnvironmentOverride;

  AppPhase _phase = AppPhase.starting;
  CoreRuntime? _runtime;
  Profile? _profile;
  VaultSession? _session;
  VaultStatus? _previewStatus;
  TargetLockInfo? _targetLock;
  String? _startupError;
  String? _unlockError;
  CoreExitCode? _unlockExit;
  bool _unlocking = false;
  bool _disposed = false;
  int _dataRevision = 0;
  int _refreshRevision = 0;
  InstanceLock? _instanceLock;

  AppPhase get phase => _phase;
  CoreRuntime? get runtime => _runtime;
  Profile? get profile => _profile;
  VaultSession? get session => _session;
  VaultStatus? get previewStatus => _previewStatus;
  TargetLockInfo? get targetLock => _targetLock;
  String? get startupError => _startupError;
  String? get unlockError => _unlockError;
  CoreExitCode? get unlockExit => _unlockExit;
  bool get unlocking => _unlocking;
  int get dataRevision => _dataRevision;
  int get refreshRevision => _refreshRevision;
  bool get isBusy => queue.isBusy;
  bool get hasInstanceLock => _instanceLock != null;

  String? get coreVersion => _runtime?.version;
  CoreBinary? get binary => _runtime?.binary;
  CoreIntegrityResult? get integrity => _runtime?.integrity;

  Future<void> initialize() async {
    _phase = AppPhase.starting;
    _startupError = null;
    _notify();
    try {
      await paths.ensure();
      if (_acquireInstanceLock && _instanceLock == null) {
        _instanceLock = await InstanceLock.acquire(paths.instanceLockFile);
        if (_instanceLock == null) {
          _phase = AppPhase.alreadyRunning;
          _notify();
          return;
        }
      }

      _runtime = await (_runtimeLoader ?? _loadRuntime)();
      final loaded = await profileStore.load();
      _profile = loaded;
      if (loaded == null) {
        _session = null;
        _phase = AppPhase.onboarding;
        _notify();
        return;
      }
      if (!loaded.vaultInitialized) {
        throw ProfileStoreException('本地控制平面缺少 vault.meta：${loaded.vaultDir}');
      }
      _session = VaultSession(
        gateway: _runtime!.gateway,
        profile: loaded,
        queue: queue,
      );
      await _loadPreviewStatus();
      await refreshTargetLock();
      _phase = AppPhase.locked;
    } catch (error) {
      _startupError = _friendlyError(error);
      _phase = AppPhase.failed;
    }
    _notify();
  }

  Future<CoreRuntime> _loadRuntime() {
    return CoreRuntime.load(
      allowEnvironmentOverride: _allowEnvironmentOverride,
    );
  }

  Future<void> retryStartup() async {
    if (queue.isBusy) return;
    _session?.lock();
    _session = null;
    await initialize();
  }

  Future<OnboardingResult> createVault({
    required String sourceRoot,
    required String targetDir,
    required String password,
    VaultSettings settings = const VaultSettings(),
    OnboardingLog? onLog,
    OnboardingStepListener? onStep,
  }) async {
    final runtime = _runtime;
    if (runtime == null) {
      return const OnboardingResult(
        success: false,
        steps: [],
        error: '核心 sidecar 不可用，无法创建库。',
      );
    }
    final integrityError = await _integrityError();
    if (integrityError != null) {
      return OnboardingResult(
        success: false,
        steps: const [],
        error: integrityError,
      );
    }
    final service = OnboardingService(
      gateway: runtime.gateway,
      paths: paths,
      store: profileStore,
      queue: queue,
    );
    return service.create(
      sourceRoot: sourceRoot,
      targetDir: targetDir,
      password: password,
      settings: settings,
      onLog: onLog,
      onStep: onStep,
    );
  }

  Future<OnboardingResult> joinVault({
    required String sourceRoot,
    required String targetDir,
    required String armorKey,
    required String password,
    VaultSettings settings = const VaultSettings(),
    OnboardingLog? onLog,
    OnboardingStepListener? onStep,
  }) async {
    final runtime = _runtime;
    if (runtime == null) {
      return const OnboardingResult(
        success: false,
        steps: [],
        error: '核心 sidecar 不可用，无法加入库。',
      );
    }
    final integrityError = await _integrityError();
    if (integrityError != null) {
      return OnboardingResult(
        success: false,
        steps: const [],
        error: integrityError,
      );
    }
    final service = OnboardingService(
      gateway: runtime.gateway,
      paths: paths,
      store: profileStore,
      queue: queue,
    );
    return service.join(
      sourceRoot: sourceRoot,
      targetDir: targetDir,
      armorKey: armorKey,
      password: password,
      settings: settings,
      onLog: onLog,
      onStep: onStep,
    );
  }

  /// 在 onboarding 成功页点击“进入应用”后调用：建立会话并解锁。
  Future<UnlockOutcome> activateProfile(
    Profile profile,
    String password,
  ) async {
    final runtime = _runtime;
    if (runtime == null) {
      return const UnlockOutcome(success: false, message: '核心 sidecar 不可用。');
    }
    _profile = profile;
    _session = VaultSession(
      gateway: runtime.gateway,
      profile: profile,
      queue: queue,
    );
    final outcome = await unlock(password);
    if (outcome.success) {
      _phase = AppPhase.unlocked;
      _unlockError = null;
      _unlockExit = null;
      _notify();
    }
    return outcome;
  }

  Future<UnlockOutcome> unlock(String password) async {
    final session = _session;
    if (session == null) {
      return const UnlockOutcome(success: false, message: '没有可解锁的 profile。');
    }
    _unlocking = true;
    _unlockError = null;
    _unlockExit = null;
    _notify();
    try {
      final integrityError = await _integrityError();
      if (integrityError != null) {
        _unlockError = integrityError;
        return UnlockOutcome(success: false, message: integrityError);
      }
      final result = await session.unlock(password);
      final ok =
          result.isSuccess && !result.protocolError && result.jsonList != null;
      if (ok) {
        _phase = AppPhase.unlocked;
        _unlockError = null;
        _unlockExit = null;
      } else {
        _unlockError = _resultMessage(result);
        _unlockExit = result.exit;
      }
      return UnlockOutcome(
        success: ok,
        result: result,
        message: ok ? null : _unlockError,
      );
    } catch (error) {
      _unlockError = '$error';
      return UnlockOutcome(success: false, message: _unlockError);
    } finally {
      _unlocking = false;
      _notify();
    }
  }

  bool lock() {
    if (queue.isBusy) return false;
    _session?.lock();
    _phase = AppPhase.locked;
    _unlockError = null;
    _unlockExit = null;
    _notify();
    return true;
  }

  void markDataChanged() {
    _dataRevision++;
    _notify();
  }

  void requestRefresh() {
    _refreshRevision++;
    _notify();
  }

  Future<void> refreshPreviewStatus() async {
    await _loadPreviewStatus();
    await refreshTargetLock();
    _notify();
  }

  Future<void> refreshTargetLock() async {
    final current = _profile;
    if (current == null) {
      _targetLock = null;
      return;
    }
    try {
      _targetLock = await TargetLockInfo.inspect(current.targetDir);
    } catch (_) {
      _targetLock = null;
    }
    _notify();
  }

  Future<void> _loadPreviewStatus() async {
    final session = _session;
    if (session == null) return;
    try {
      final result = await session.status();
      final map = result.jsonMap;
      if (result.isSuccess && map != null) {
        _previewStatus = VaultStatus.fromJson(map);
      }
    } catch (_) {
      _previewStatus = null;
    }
  }

  Future<void> updateVaultSettings(VaultSettings settings) async {
    if (queue.isBusy) throw StateError('运行中的命令结束后才能修改参数。');
    final current = _profile;
    if (current == null) throw StateError('没有活动 profile。');
    final error = settings.validate();
    if (error != null) throw ArgumentError(error);
    final updated = current.copyWith(settings: settings);
    await profileStore.saveWithConfig(updated);
    _profile = updated;
    _session?.updateProfile(updated);
    _notify();
  }

  Future<void> updateSessionLimit(int mib) async {
    final current = _profile;
    if (current == null) throw StateError('没有活动 profile。');
    await updateVaultSettings(current.settings.copyWith(sessionMaxMib: mib));
  }

  Future<void> forgetProfile() => resetLocalConfig();

  /// 删除本地 profile/config/控制平面；TargetDir 与其他备份数据不受影响。
  Future<void> resetLocalConfig() async {
    if (queue.isBusy) throw StateError('运行中的命令结束后才能移除配置。');
    _session?.lock();
    _session = null;
    _profile = null;
    _previewStatus = null;
    _targetLock = null;
    _unlockError = null;
    _unlockExit = null;
    await profileStore.forget(deleteVault: true);
    if (_runtime == null) {
      _phase = AppPhase.failed;
      _startupError = '本地配置已移除，但核心 sidecar 仍不可用。';
    } else {
      _phase = AppPhase.onboarding;
      _startupError = null;
    }
    _notify();
  }

  Future<void> quit({bool force = false}) async {
    if (queue.isBusy) {
      if (!force) throw StateError('仍有命令在运行。');
      await queue.cancelCurrent();
      await queue.waitForIdle();
    }
    await _instanceLock?.release();
    _instanceLock = null;
    exit(0);
  }

  Future<String?> _integrityError() async {
    final runtime = _runtime;
    if (runtime == null) return '核心 sidecar 不可用。';
    try {
      final integrity = await runtime.binary.verifyIntegrity();
      if (integrity.isAcceptable) return null;
      return 'sidecar 完整性校验失败（${integrity.status.name}），已拒绝执行。';
    } catch (error) {
      return 'sidecar 完整性校验失败：$error';
    }
  }

  String _resultMessage(CoreResult result) {
    final summary = result.errorSummary;
    final extra = summary == result.exit.label ? '' : '\n$summary';
    return '${result.exit.label}（exit ${result.exitCode}）· ${result.exit.guidance}$extra';
  }

  String _friendlyError(Object error) {
    if (error is CoreRuntimeException) return error.message;
    if (error is ProfileStoreException) return error.message;
    if (error is FileSystemException) {
      return '${error.message}：${error.path ?? ''}';
    }
    return '$error';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session?.lock();
    queue.dispose();
    unawaited(_instanceLock?.release());
    super.dispose();
  }
}

typedef CoreRuntimeLoader = Future<CoreRuntime> Function();
