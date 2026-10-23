import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_paths.dart';
import '../core/app_preferences.dart';
import '../core/backup_schedule.dart';
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
import '../core/workspace_store.dart';

enum AppPhase { starting, alreadyRunning, failed, onboarding, locked, unlocked }

enum WorkspaceSetupMode { create, import }

class UnlockOutcome {
  const UnlockOutcome({required this.success, this.result, this.message});

  final bool success;
  final CoreResult? result;
  final String? message;
}

class AppController extends ChangeNotifier {
  AppController({
    required this.paths,
    WorkspaceStore? workspaceStore,
    AppPreferencesStore? preferencesStore,
    CommandQueue? queue,
    CoreRuntimeLoader? runtimeLoader,
    this.platform = const PlatformService(),
    bool acquireInstanceLock = true,
    bool allowEnvironmentOverride = kDebugMode,
  }) : workspaceStore = workspaceStore ?? WorkspaceStore(paths),
       preferencesStore = preferencesStore ?? AppPreferencesStore(paths),
       queue = queue ?? CommandQueue(),
       // ignore: prefer_initializing_formals
       _runtimeLoader = runtimeLoader,
       // ignore: prefer_initializing_formals
       _acquireInstanceLock = acquireInstanceLock,
       // ignore: prefer_initializing_formals
       _allowEnvironmentOverride = allowEnvironmentOverride;

  final AppPaths paths;
  final WorkspaceStore workspaceStore;
  final AppPreferencesStore preferencesStore;
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
  int _workspaceRevision = 0;
  InstanceLock? _instanceLock;
  AppThemeMode _themeMode = AppThemeMode.light;
  Timer? _scheduleTimer;
  bool _scheduledBackupRunning = false;
  int _scheduledBackupRevision = 0;
  String? _lastScheduledBackupMessage;
  WorkspaceSetupMode? _workspaceSetupMode;

  AppPhase get phase => _phase;
  ProfileStore get profileStore => workspaceStore.requireActiveStore();
  List<WorkspaceInfo> get workspaces => workspaceStore.workspaces;
  WorkspaceInfo? get activeWorkspace => workspaceStore.activeWorkspace;
  WorkspaceSetupMode? get workspaceSetupMode => _workspaceSetupMode;
  bool get hasWorkspaces => workspaceStore.hasWorkspaces;
  bool get hasDraftWorkspace => workspaceStore.hasDraft;
  AppPaths? get activeWorkspacePaths => workspaceStore.activePaths;
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
  int get workspaceRevision => _workspaceRevision;
  AppThemeMode get themeMode => _themeMode;
  BackupSchedule get backupSchedule =>
      _profile?.schedule ?? const BackupSchedule();
  DateTime? get nextScheduledBackup => backupSchedule.nextRunAt;
  bool get scheduledBackupRunning => _scheduledBackupRunning;
  int get scheduledBackupRevision => _scheduledBackupRevision;
  String? get lastScheduledBackupMessage => _lastScheduledBackupMessage;
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
      await workspaceStore.initialize();
      _themeMode = (await preferencesStore.load()).themeMode;

      _runtime = await (_runtimeLoader ?? _loadRuntime)();
      await _loadActiveWorkspace();
    } catch (error) {
      _startupError = _friendlyError(error);
      _phase = AppPhase.failed;
    }
    _restartScheduleTimer();
    _notify();
  }

  Future<void> _loadActiveWorkspace() async {
    _profile = null;
    _session = null;
    _previewStatus = null;
    _targetLock = null;
    _unlockError = null;
    _unlockExit = null;
    final store = workspaceStore.activeStore;
    if (store == null) {
      _phase = AppPhase.onboarding;
      return;
    }
    var loaded = await store.load();
    if (loaded != null &&
        loaded.schedule.isEnabled &&
        loaded.schedule.nextRunAt == null) {
      final next = loaded.schedule.nextAfter(DateTime.now());
      if (next != null) {
        loaded = loaded.copyWith(
          schedule: loaded.schedule.copyWith(
            nextRunAt: next,
            clearLastError: true,
          ),
        );
        try {
          await store.save(loaded);
        } catch (_) {
          // 定时计划不应阻塞启动；内存中的 nextRunAt 仍可使用。
        }
      }
    }
    _profile = loaded;
    if (loaded == null) {
      _phase = AppPhase.onboarding;
      return;
    }
    if (!loaded.vaultInitialized) {
      throw ProfileStoreException('本地控制平面缺少 vault.meta：${loaded.vaultDir}');
    }
    final runtime = _runtime;
    if (runtime == null) {
      throw const WorkspaceStoreException('核心 sidecar 不可用，无法打开工作区。');
    }
    _session = VaultSession(
      gateway: runtime.gateway,
      profile: loaded,
      queue: queue,
    );
    await _loadPreviewStatus();
    await refreshTargetLock();
    await workspaceStore.refreshActiveMetadata(loaded);
    _phase = AppPhase.locked;
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
    final activePaths = workspaceStore.activePaths;
    final store = workspaceStore.activeStore;
    if (activePaths == null || store == null) {
      return const OnboardingResult(
        success: false,
        steps: [],
        error: '没有可用于创建的工作区目录。',
      );
    }
    final service = OnboardingService(
      gateway: runtime.gateway,
      paths: activePaths,
      store: store,
      queue: queue,
    );
    final result = await service.create(
      sourceRoot: sourceRoot,
      targetDir: targetDir,
      password: password,
      settings: settings,
      onLog: onLog,
      onStep: onStep,
    );
    if (result.success && result.profile != null) {
      try {
        await workspaceStore.commitDraft(result.profile!);
        _workspaceSetupMode = null;
      } catch (error) {
        return OnboardingResult(
          success: false,
          steps: result.steps,
          error: '工作区已创建，但保存工作区索引失败：$error',
          profile: result.profile,
          key: result.key,
        );
      }
    }
    return result;
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
    final activePaths = workspaceStore.activePaths;
    final store = workspaceStore.activeStore;
    if (activePaths == null || store == null) {
      return const OnboardingResult(
        success: false,
        steps: [],
        error: '没有可用于导入的工作区目录。',
      );
    }
    final service = OnboardingService(
      gateway: runtime.gateway,
      paths: activePaths,
      store: store,
      queue: queue,
    );
    final result = await service.join(
      sourceRoot: sourceRoot,
      targetDir: targetDir,
      armorKey: armorKey,
      password: password,
      settings: settings,
      onLog: onLog,
      onStep: onStep,
    );
    if (result.success && result.profile != null) {
      try {
        await workspaceStore.commitDraft(result.profile!);
        _workspaceSetupMode = null;
      } catch (error) {
        return OnboardingResult(
          success: false,
          steps: result.steps,
          error: '工作区已导入，但保存工作区索引失败：$error',
          profile: result.profile,
          key: result.key,
        );
      }
    }
    return result;
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
    if (workspaceStore.hasDraft) {
      try {
        await workspaceStore.commitDraft(profile);
      } catch (error) {
        return UnlockOutcome(success: false, message: '保存工作区索引失败：$error');
      }
    }
    _workspaceSetupMode = null;
    await workspaceStore.refreshActiveMetadata(profile);
    _profile = profile;
    _session = VaultSession(
      gateway: runtime.gateway,
      profile: profile,
      queue: queue,
    );
    final outcome = await unlock(password);
    if (outcome.success) {
      _workspaceRevision++;
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
        _restartScheduleTimer();
        unawaited(_checkScheduledBackup());
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

  Future<void> setThemeMode(AppThemeMode mode) async {
    if (_themeMode == mode) return;
    final previous = _themeMode;
    _themeMode = mode;
    _notify();
    try {
      await preferencesStore.save(AppPreferences(themeMode: mode));
    } catch (error) {
      _themeMode = previous;
      _notify();
      throw StateError('无法保存外观设置：$error');
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

  Future<void> updateBackupSchedule(BackupSchedule schedule) async {
    if (_scheduledBackupRunning) {
      throw StateError('定时备份正在运行，结束后再修改计划。');
    }
    final current = _profile;
    if (current == null) throw StateError('没有活动 profile。');
    final error = schedule.validate();
    if (error != null) throw ArgumentError(error);
    final next = schedule.isEnabled ? schedule.nextAfter(DateTime.now()) : null;
    final normalized = schedule.copyWith(
      nextRunAt: next,
      clearNextRunAt: next == null,
      clearLastError: true,
    );
    final updated = current.copyWith(schedule: normalized);
    await profileStore.save(updated);
    _profile = updated;
    _session?.updateProfile(updated);
    _restartScheduleTimer();
    _notify();
    unawaited(_checkScheduledBackup());
  }

  void _restartScheduleTimer() {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    if (_profile?.schedule.isEnabled != true) return;
    _scheduleTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_checkScheduledBackup());
    });
  }

  Future<void> _checkScheduledBackup() async {
    if (_disposed || _scheduledBackupRunning) return;
    final current = _profile;
    final session = _session;
    if (current == null || session == null || _phase != AppPhase.unlocked) {
      return;
    }
    final schedule = current.schedule;
    final next = schedule.nextRunAt;
    if (!schedule.isEnabled ||
        next == null ||
        next.toLocal().isAfter(DateTime.now()) ||
        queue.isBusy) {
      return;
    }

    _scheduledBackupRunning = true;
    _notify();
    var message = '';
    try {
      final result = await session.backup(message: '定时备份');
      if (_disposed) return;
      final completed = DateTime.now();
      final nextAt = schedule.nextAfter(completed);
      if (result.isSuccess) {
        await _loadPreviewStatus();
        await refreshTargetLock();
        _dataRevision++;
        final summary = result.jsonMap == null
            ? null
            : BackupSummary.fromJson(result.jsonMap!);
        message = summary == null ? '定时备份完成' : '定时备份完成 · seq ${summary.seq}';
        await _persistSchedule(
          schedule.copyWith(
            lastRunAt: completed,
            nextRunAt: nextAt,
            clearLastError: true,
          ),
        );
      } else {
        final error = _resultMessage(result);
        message = '定时备份失败 · ${result.exit.label}';
        await _persistSchedule(
          schedule.copyWith(
            lastRunAt: completed,
            nextRunAt: nextAt,
            lastError: error,
          ),
        );
      }
    } catch (error) {
      if (!_disposed) {
        final completed = DateTime.now();
        final nextAt = schedule.nextAfter(completed);
        message = '定时备份失败 · $error';
        try {
          await _persistSchedule(
            schedule.copyWith(
              lastRunAt: completed,
              nextRunAt: nextAt,
              lastError: '$error',
            ),
          );
        } catch (_) {
          // 计划已到点；保留内存状态，避免每秒重试。
        }
      }
    } finally {
      if (!_disposed) {
        _scheduledBackupRunning = false;
        _lastScheduledBackupMessage = message;
        _scheduledBackupRevision++;
        _notify();
      }
    }
  }

  Future<void> _persistSchedule(BackupSchedule schedule) async {
    final current = _profile;
    if (current == null) return;
    final updated = current.copyWith(schedule: schedule);
    await profileStore.save(updated);
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
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _session?.lock();
    _session = null;
    _profile = null;
    _previewStatus = null;
    _targetLock = null;
    _unlockError = null;
    _unlockExit = null;
    _workspaceSetupMode = null;
    await workspaceStore.forgetActive();
    if (_runtime == null) {
      _phase = AppPhase.failed;
      _startupError = '本地配置已移除，但核心 sidecar 仍不可用。';
    } else {
      await _loadActiveWorkspace();
      _startupError = null;
    }
    _workspaceRevision++;
    _notify();
  }

  Future<void> beginWorkspaceSetup(WorkspaceSetupMode mode) async {
    if (queue.isBusy) {
      throw StateError('运行中的命令结束后才能切换工作区。');
    }
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _session?.lock();
    _session = null;
    _profile = null;
    _previewStatus = null;
    _targetLock = null;
    _unlockError = null;
    _unlockExit = null;
    await workspaceStore.beginDraft();
    _workspaceSetupMode = mode;
    _startupError = null;
    _workspaceRevision++;
    _phase = AppPhase.onboarding;
    _notify();
  }

  Future<void> cancelWorkspaceSetup() async {
    if (queue.isBusy) throw StateError('运行中的命令结束后才能返回。');
    _workspaceSetupMode = null;
    if (workspaceStore.hasDraft) {
      await workspaceStore.cancelDraft();
    }
    _session?.lock();
    _session = null;
    _profile = null;
    _previewStatus = null;
    _targetLock = null;
    _unlockError = null;
    _unlockExit = null;
    try {
      await _loadActiveWorkspace();
      _startupError = null;
    } catch (error) {
      _startupError = _friendlyError(error);
      _phase = AppPhase.failed;
    }
    _workspaceRevision++;
    _restartScheduleTimer();
    _notify();
  }

  Future<String?> switchWorkspace(String id) async {
    if (queue.isBusy) return '命令运行中，结束后才能切换工作区。';
    if (workspaceStore.activeWorkspace?.id == id) return null;
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _session?.lock();
    _session = null;
    _profile = null;
    _previewStatus = null;
    _targetLock = null;
    _unlockError = null;
    _unlockExit = null;
    _workspaceSetupMode = null;
    try {
      await workspaceStore.switchTo(id);
      await _loadActiveWorkspace();
      _startupError = null;
      _workspaceRevision++;
      _restartScheduleTimer();
      _notify();
      return null;
    } catch (error) {
      _startupError = _friendlyError(error);
      _phase = AppPhase.failed;
      _notify();
      return _startupError;
    }
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
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _session?.lock();
    queue.dispose();
    unawaited(_instanceLock?.release());
    super.dispose();
  }
}

typedef CoreRuntimeLoader = Future<CoreRuntime> Function();
