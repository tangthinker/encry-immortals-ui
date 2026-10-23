import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'app_paths.dart';
import 'private_file.dart';
import 'profile.dart';
import 'profile_store.dart';

/// A named workspace is one vault profile, one config.toml and one local
/// control plane. The TargetDir itself stays wherever the user put it.
class WorkspaceInfo {
  const WorkspaceInfo({
    required this.id,
    required this.name,
    required this.directory,
    this.targetDir,
    this.lastOpenedAt,
  });

  final String id;
  final String name;
  final String directory;
  final String? targetDir;
  final DateTime? lastOpenedAt;

  AppPaths get paths => AppPaths(root: directory);

  bool get hasProfile => File(p.join(directory, 'profile.json')).existsSync();

  WorkspaceInfo copyWith({
    String? name,
    String? targetDir,
    DateTime? lastOpenedAt,
  }) {
    return WorkspaceInfo(
      id: id,
      name: name ?? this.name,
      directory: directory,
      targetDir: targetDir ?? this.targetDir,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'directory': directory,
    if (targetDir != null) 'target_dir': targetDir,
    if (lastOpenedAt != null)
      'last_opened_at': lastOpenedAt!.toUtc().toIso8601String(),
  };
}

class WorkspaceStoreException implements Exception {
  const WorkspaceStoreException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message（$cause）';
}

/// Owns the global workspace index and keeps the active workspace paths.
///
/// Directory layout:
///
/// ```text
/// <app root>/
///   preferences.json
///   instance.lock
///   workspaces.json
///   workspaces/<id>/profile.json
///   workspaces/<id>/config.toml
///   workspaces/<id>/vault/
/// ```
///
/// While a new workspace is being created/imported, its directory is a
/// temporary draft: it uses `workspaces/<id>/` but is not written to
/// `workspaces.json` until onboarding succeeds. A crash leaves an orphan draft
/// which is ignored on the next launch.
class WorkspaceStore {
  WorkspaceStore(this.appPaths);

  static const int currentSchema = 1;

  final AppPaths appPaths;
  final List<WorkspaceInfo> _workspaces = [];

  String? _activeId;
  String? _draftId;
  AppPaths? _draftPaths;
  ProfileStore? _draftStore;
  String? _activeBeforeDraft;
  ProfileStore? _activeStore;
  bool _initialized = false;

  bool get initialized => _initialized;
  bool get hasWorkspaces => _workspaces.isNotEmpty;
  bool get hasDraft => _draftId != null && _draftPaths != null;

  List<WorkspaceInfo> get workspaces => List.unmodifiable(_workspaces);

  WorkspaceInfo? get activeWorkspace {
    final id = _activeId;
    if (id == null || id == _draftId) return null;
    for (final workspace in _workspaces) {
      if (workspace.id == id) return workspace;
    }
    return null;
  }

  String? get activeId => _activeId;

  AppPaths? get activePaths => _draftPaths ?? activeWorkspace?.paths;

  ProfileStore? get activeStore =>
      _draftStore ?? (activeWorkspace == null ? null : _activeStore);

  ProfileStore requireActiveStore() {
    final store = activeStore;
    if (store == null) {
      throw const WorkspaceStoreException('当前没有活动工作区。');
    }
    return store;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    await appPaths.ensure();
    await Directory(appPaths.workspacesDir).create(recursive: true);

    final index = await _readIndex();
    await _migrateLegacyIfNeeded(index);
    final scanned = await _scanWorkspaces(index);

    _workspaces
      ..clear()
      ..addAll(scanned);
    _sortWorkspaces();
    if (_workspaces.isNotEmpty) {
      final persistedActive = index?.activeId;
      final activeExists =
          persistedActive != null &&
          _workspaces.any((workspace) => workspace.id == persistedActive);
      final fallback = _workspaces.first.id;
      _setActiveReal(activeExists ? persistedActive : fallback);
      final current = activeWorkspace;
      if (current != null) {
        _replaceWorkspace(current.copyWith(lastOpenedAt: DateTime.now()));
      }
    } else {
      await beginDraft();
    }
    _initialized = true;
    await _writeIndex();
  }

  /// Starts a draft workspace used by onboarding. Existing workspaces stay in
  /// the index and become active again if the draft is cancelled.
  Future<void> beginDraft() async {
    if (hasDraft) return;
    _activeBeforeDraft ??= activeWorkspace?.id;
    final id = _newId();
    final directory = appPaths.workspaceDir(id);
    await Directory(directory).create(recursive: true);
    _draftId = id;
    _draftPaths = AppPaths(root: directory);
    _draftStore = ProfileStore(_draftPaths!);
    _activeId = id;
    _activeStore = null;
    await _writeIndex();
  }

  /// Called after onboarding wrote profile/config/vault into the draft.
  Future<void> commitDraft(Profile profile) async {
    final id = _draftId;
    final paths = _draftPaths;
    if (id == null || paths == null) {
      throw const WorkspaceStoreException('没有可提交的工作区草稿。');
    }
    if (!File(paths.profileFile).existsSync()) {
      throw WorkspaceStoreException(
        '工作区草稿缺少 profile.json：${paths.profileFile}',
      );
    }
    final info = WorkspaceInfo(
      id: id,
      name: profile.name,
      directory: paths.root,
      targetDir: profile.targetDir,
      lastOpenedAt: DateTime.now(),
    );
    _workspaces.removeWhere((workspace) => workspace.id == id);
    _workspaces.add(info);
    _sortWorkspaces();
    _draftId = null;
    _draftPaths = null;
    _draftStore = null;
    _activeId = id;
    _activeStore = ProfileStore(paths);
    _activeBeforeDraft = null;
    await _writeIndex();
  }

  /// Called when the user leaves onboarding before creating a profile.
  Future<void> cancelDraft() async {
    final draftPaths = _draftPaths;
    _draftId = null;
    _draftPaths = null;
    _draftStore = null;
    if (draftPaths != null) {
      // Delete only the app-owned profile/config/vault, then remove the
      // directory only if it is empty. Never recursively remove a directory a
      // user might have picked as TargetDir.
      try {
        await ProfileStore(draftPaths).forget(deleteVault: true);
      } catch (_) {}
      final directory = Directory(draftPaths.root);
      if (await directory.exists()) {
        try {
          await directory.delete();
        } catch (_) {}
      }
    }

    final previous = _activeBeforeDraft;
    _activeBeforeDraft = null;
    if (previous != null &&
        _workspaces.any((workspace) => workspace.id == previous)) {
      _setActiveReal(previous);
    } else if (_workspaces.isNotEmpty) {
      _setActiveReal(_workspaces.first.id);
    } else {
      _activeId = null;
      _activeStore = null;
      _activeBeforeDraft = null;
      await _writeIndex();
      await beginDraft();
      return;
    }
    await _writeIndex();
  }

  Future<void> switchTo(String id) async {
    if (hasDraft) {
      throw const WorkspaceStoreException('请先完成或取消当前新建工作区。');
    }
    final index = _workspaces.indexWhere((workspace) => workspace.id == id);
    if (index < 0) {
      throw WorkspaceStoreException('找不到工作区：$id');
    }
    _workspaces[index] = _workspaces[index].copyWith(
      lastOpenedAt: DateTime.now(),
    );
    _sortWorkspaces();
    _setActiveReal(id);
    await _writeIndex();
  }

  /// Removes the active workspace's profile/config/control plane. TargetDir is
  /// untouched. The next available workspace becomes active, or onboarding
  /// starts again.
  Future<void> forgetActive() async {
    if (hasDraft) {
      // Resetting from onboarding means "throw away this partial setup and
      // retry", not "go back to the previous workspace".
      await cancelDraft();
      await beginDraft();
      await _writeIndex();
      return;
    }

    final active = activeWorkspace;
    if (active != null) {
      await ProfileStore(active.paths).forget(deleteVault: true);
      _workspaces.removeWhere((workspace) => workspace.id == active.id);
    }
    _activeId = null;
    _activeStore = null;
    if (_workspaces.isNotEmpty) {
      _setActiveReal(_workspaces.first.id);
    } else {
      await _writeIndex();
      await beginDraft();
      return;
    }
    await _writeIndex();
  }

  Future<void> refreshActiveMetadata(Profile profile) async {
    final active = activeWorkspace;
    if (active == null) return;
    _replaceWorkspace(
      active.copyWith(
        name: profile.name,
        targetDir: profile.targetDir,
        lastOpenedAt: DateTime.now(),
      ),
    );
    await _writeIndex();
  }

  Future<void> markActiveOpened() async {
    final active = activeWorkspace;
    if (active == null) return;
    _replaceWorkspace(active.copyWith(lastOpenedAt: DateTime.now()));
    await _writeIndex();
  }

  void _setActiveReal(String id) {
    _draftId = null;
    _draftPaths = null;
    _draftStore = null;
    _activeId = id;
    _activeStore = ProfileStore(appPaths.workspacePaths(id));
  }

  void _replaceWorkspace(WorkspaceInfo workspace) {
    final index = _workspaces.indexWhere((item) => item.id == workspace.id);
    if (index >= 0) _workspaces[index] = workspace;
  }

  void _sortWorkspaces() {
    _workspaces.sort((a, b) {
      final aTime = a.lastOpenedAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.lastOpenedAt?.millisecondsSinceEpoch ?? 0;
      final byTime = bTime.compareTo(aTime);
      return byTime != 0 ? byTime : a.name.compareTo(b.name);
    });
  }

  Future<_WorkspaceIndex?> _readIndex() async {
    final file = File(appPaths.workspacesIndexFile);
    if (!await file.exists()) return null;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      final active = raw['active'] as String?;
      final entries = <String, WorkspaceInfo>{};
      final rawWorkspaces = raw['workspaces'];
      if (rawWorkspaces is List) {
        for (final item in rawWorkspaces) {
          if (item is! Map) continue;
          final id = item['id'];
          final name = item['name'];
          final directory = item['directory'];
          if (id is! String || name is! String || directory is! String) {
            continue;
          }
          DateTime? lastOpened;
          final rawTime = item['last_opened_at'];
          if (rawTime is String) lastOpened = DateTime.tryParse(rawTime);
          entries[id] = WorkspaceInfo(
            id: id,
            name: name,
            directory: directory,
            targetDir: item['target_dir'] is String
                ? item['target_dir'] as String
                : null,
            lastOpenedAt: lastOpened,
          );
        }
      }
      return _WorkspaceIndex(activeId: active, entries: entries);
    } catch (_) {
      return null;
    }
  }

  Future<List<WorkspaceInfo>> _scanWorkspaces(_WorkspaceIndex? index) async {
    final result = <WorkspaceInfo>[];
    final directory = Directory(appPaths.workspacesDir);
    if (!await directory.exists()) return result;
    await for (final entity in directory.list()) {
      if (entity is! Directory) continue;
      final id = p.basename(entity.path);
      if (id == _draftId) continue;
      final profileFile = File(p.join(entity.path, 'profile.json'));
      if (!await profileFile.exists()) continue;
      try {
        final raw = jsonDecode(await profileFile.readAsString());
        if (raw is! Map) continue;
        final profile = Profile.fromJson(
          raw.map((key, value) => MapEntry('$key', value)),
        );
        final prior = index?.entries[id];
        result.add(
          WorkspaceInfo(
            id: id,
            name: profile.name,
            directory: entity.path,
            targetDir: profile.targetDir,
            lastOpenedAt: prior?.lastOpenedAt,
          ),
        );
      } catch (_) {
        // A corrupt profile is skipped until the user resets it from the UI.
        // Do not hide the rest of the workspaces because of one bad entry.
      }
    }
    return result;
  }

  Future<void> _migrateLegacyIfNeeded(_WorkspaceIndex? index) async {
    if (index != null) return;
    final legacyProfileFile = File(appPaths.profileFile);
    if (!await legacyProfileFile.exists()) return;

    final raw = await legacyProfileFile.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const WorkspaceStoreException('旧 profile.json 顶层必须是对象。');
    }
    final oldProfile = Profile.fromJson(
      decoded.map((key, value) => MapEntry('$key', value)),
    );
    final id = _safeId(oldProfile.id);
    final workspacePaths = appPaths.workspacePaths(id);
    final workspaceDir = Directory(workspacePaths.root);
    await workspaceDir.create(recursive: true);

    final newProfileFile = File(workspacePaths.profileFile);
    final legacyConfig = File(appPaths.configFile);
    final newConfig = File(workspacePaths.configFile);
    final legacyVault = Directory(appPaths.vaultDir);
    final newVault = Directory(workspacePaths.vaultDir);

    var movedProfile = false;
    var movedConfig = false;
    var movedVault = false;
    try {
      await legacyProfileFile.rename(newProfileFile.path);
      movedProfile = true;
      if (await legacyConfig.exists()) {
        await legacyConfig.rename(newConfig.path);
        movedConfig = true;
      }
      if (await legacyVault.exists()) {
        await legacyVault.rename(newVault.path);
        movedVault = true;
      }
      final updated = oldProfile.copyWith(
        vaultDir: workspacePaths.vaultDir,
        configPath: workspacePaths.configFile,
      );
      final store = ProfileStore(workspacePaths);
      await store.writeConfig(updated);
      await store.save(updated);
      final info = WorkspaceInfo(
        id: id,
        name: updated.name,
        directory: workspacePaths.root,
        targetDir: updated.targetDir,
        lastOpenedAt: DateTime.now(),
      );
      _workspaces
        ..removeWhere((workspace) => workspace.id == id)
        ..add(info);
      _activeId = id;
      _activeStore = store;
      await _writeIndex();
    } catch (error) {
      // Best-effort rollback so a failed migration never destroys the only
      // local control plane.
      if (movedProfile &&
          await newProfileFile.exists() &&
          !await legacyProfileFile.exists()) {
        await _renameQuietly(newProfileFile, legacyProfileFile.path);
      }
      if (movedConfig &&
          await newConfig.exists() &&
          !await legacyConfig.exists()) {
        await _renameQuietly(newConfig, legacyConfig.path);
      }
      if (movedVault &&
          await newVault.exists() &&
          !await legacyVault.exists()) {
        await _renameQuietly(newVault, legacyVault.path);
      }
      throw WorkspaceStoreException('迁移旧工作区失败；原数据已尽量保留。', error);
    }
  }

  Future<void> _renameQuietly(FileSystemEntity source, String target) async {
    try {
      await source.rename(target);
    } catch (_) {}
  }

  Future<void> _writeIndex() async {
    final file = File(appPaths.workspacesIndexFile);
    final tmp = File('${file.path}.tmp');
    await tmp.parent.create(recursive: true);
    final active = activeWorkspace?.id ?? _activeBeforeDraft;
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema': currentSchema,
        'active': active,
        'workspaces': [for (final workspace in _workspaces) workspace.toJson()],
      }),
      flush: true,
    );
    await makePrivateFile(tmp.path);
    if (Platform.isWindows && await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }

  String _newId() {
    final random = Random.secure();
    final suffix = List<String>.generate(
      8,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    return 'ws-${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}-$suffix';
  }

  String _safeId(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '-');
    if (cleaned.isEmpty) return _newId();
    return cleaned;
  }
}

class _WorkspaceIndex {
  const _WorkspaceIndex({required this.activeId, required this.entries});

  final String? activeId;
  final Map<String, WorkspaceInfo> entries;
}
