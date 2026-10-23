import 'dart:io';

import 'package:encry_immortals_ui/core/app_paths.dart';
import 'package:encry_immortals_ui/core/profile.dart';
import 'package:encry_immortals_ui/core/profile_store.dart';
import 'package:encry_immortals_ui/core/workspace_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Profile profileFor(
  AppPaths paths, {
  required String id,
  required String name,
  required String targetDir,
  required String sourceRoot,
}) {
  Directory(paths.vaultDir).createSync(recursive: true);
  File(p.join(paths.vaultDir, 'vault.meta')).writeAsStringSync('{}');
  return Profile(
    id: id,
    name: name,
    vaultDir: paths.vaultDir,
    targetDir: targetDir,
    configPath: paths.configFile,
    sourceRoot: sourceRoot,
    mode: ProfileMode.created,
    createdAt: DateTime.utc(2026, 10, 24),
    sessionMaxMib: 64,
  );
}

void main() {
  late Directory temp;
  late AppPaths root;
  late String source;
  late String target;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('eimmortal_workspace_');
    root = AppPaths(root: p.join(temp.path, 'app'));
    await root.ensure();
    source = p.join(temp.path, 'source');
    target = p.join(temp.path, 'target');
    await Directory(source).create();
    await Directory(target).create();
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  test('旧单工作区自动迁移到 workspaces/<id>', () async {
    final legacy = profileFor(
      root,
      id: 'legacy-id',
      name: '旧工作区',
      targetDir: target,
      sourceRoot: source,
    );
    await ProfileStore(root).saveWithConfig(legacy);
    expect(File(root.profileFile).existsSync(), isTrue);

    final store = WorkspaceStore(root);
    await store.initialize();

    expect(store.workspaces, hasLength(1));
    final active = store.activeWorkspace!;
    expect(active.name, '旧工作区');
    expect(active.id, 'legacy-id');
    expect(File(root.profileFile).existsSync(), isFalse);
    expect(File(root.configFile).existsSync(), isFalse);
    expect(Directory(root.vaultDir).existsSync(), isFalse);

    final migrated = await ProfileStore(active.paths).load();
    expect(migrated, isNotNull);
    expect(migrated!.vaultDir, active.paths.vaultDir);
    expect(migrated.configPath, active.paths.configFile);
    expect(File(active.paths.configFile).existsSync(), isTrue);
    expect(Directory(active.paths.vaultDir).existsSync(), isTrue);
    expect(File(root.workspacesIndexFile).existsSync(), isTrue);
  });

  test('草稿提交、切换和取消草稿', () async {
    final store = WorkspaceStore(root);
    await store.initialize();
    expect(store.hasDraft, isTrue);
    expect(store.workspaces, isEmpty);

    final firstPaths = store.activePaths!;
    final first = profileFor(
      firstPaths,
      id: 'first',
      name: '工作区 A',
      targetDir: target,
      sourceRoot: source,
    );
    await ProfileStore(firstPaths).saveWithConfig(first);
    await store.commitDraft(first);

    expect(store.hasDraft, isFalse);
    expect(store.activeWorkspace!.name, '工作区 A');
    final firstId = store.activeWorkspace!.id;
    expect(store.workspaces, hasLength(1));

    await store.beginDraft();
    final secondPaths = store.activePaths!;
    final second = profileFor(
      secondPaths,
      id: 'second',
      name: '工作区 B',
      targetDir: p.join(temp.path, 'target-b'),
      sourceRoot: source,
    );
    await ProfileStore(secondPaths).saveWithConfig(second);
    await store.commitDraft(second);
    expect(store.activeWorkspace!.name, '工作区 B');
    expect(store.workspaces, hasLength(2));

    await store.switchTo(firstId);
    expect(store.activeWorkspace!.name, '工作区 A');
    expect(store.activePaths!.profileFile, firstPaths.profileFile);

    await store.beginDraft();
    await store.cancelDraft();
    expect(store.hasDraft, isFalse);
    expect(store.activeWorkspace!.name, '工作区 A');
    expect(store.workspaces, hasLength(2));

    final reloaded = WorkspaceStore(root);
    await reloaded.initialize();
    expect(reloaded.workspaces, hasLength(2));
    expect(reloaded.activeWorkspace!.name, '工作区 A');
  });

  test('移除活动工作区后切换到下一个或回到 onboarding', () async {
    final store = WorkspaceStore(root);
    await store.initialize();
    final firstPaths = store.activePaths!;
    final first = profileFor(
      firstPaths,
      id: 'first',
      name: 'A',
      targetDir: target,
      sourceRoot: source,
    );
    await ProfileStore(firstPaths).saveWithConfig(first);
    await store.commitDraft(first);

    await store.forgetActive();
    expect(store.hasDraft, isTrue);
    expect(store.workspaces, isEmpty);
    expect(File(firstPaths.profileFile).existsSync(), isFalse);
    expect(File(firstPaths.configFile).existsSync(), isFalse);
    expect(Directory(firstPaths.vaultDir).existsSync(), isFalse);
  });
}
