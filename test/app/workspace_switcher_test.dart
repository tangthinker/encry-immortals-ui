import 'dart:io';

import 'package:encry_immortals_ui/app/app_controller.dart';
import 'package:encry_immortals_ui/app/widgets/workspace_switcher.dart';
import 'package:encry_immortals_ui/core/app_paths.dart';
import 'package:encry_immortals_ui/core/profile.dart';
import 'package:encry_immortals_ui/core/profile_store.dart';
import 'package:encry_immortals_ui/core/workspace_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Profile makeProfile(
  AppPaths paths, {
  required String id,
  required String name,
  required String sourceRoot,
  required String targetDir,
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
  );
}

void main() {
  testWidgets('工作区弹窗列出全部工作区和新建/导入入口', (tester) async {
    late Directory temp;
    late WorkspaceStore store;
    late AppController controller;
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('eimmortal_ws_ui_');
      final root = AppPaths(root: p.join(temp.path, 'app'));
      await root.ensure();
      final source = Directory(p.join(temp.path, 'source'))..createSync();
      final targetA = Directory(p.join(temp.path, 'target-a'))..createSync();
      final targetB = Directory(p.join(temp.path, 'target-b'))..createSync();

      store = WorkspaceStore(root);
      await store.initialize();

      final firstPaths = store.activePaths!;
      final first = makeProfile(
        firstPaths,
        id: 'first',
        name: '工作区 A',
        sourceRoot: source.path,
        targetDir: targetA.path,
      );
      await ProfileStore(firstPaths).saveWithConfig(first);
      await store.commitDraft(first);

      await store.beginDraft();
      final secondPaths = store.activePaths!;
      final second = makeProfile(
        secondPaths,
        id: 'second',
        name: '工作区 B',
        sourceRoot: source.path,
        targetDir: targetB.path,
      );
      await ProfileStore(secondPaths).saveWithConfig(second);
      await store.commitDraft(second);

      controller = AppController(
        paths: root,
        workspaceStore: store,
        acquireInstanceLock: false,
      );
    });
    addTearDown(() async {
      controller.dispose();
      if (temp.existsSync()) await temp.delete(recursive: true);
    });

    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWorkspaceSwitcher(context, controller),
              child: const Text('打开工作区'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开工作区'));
    await tester.pumpAndSettle();

    expect(find.text('工作区'), findsOneWidget);
    expect(find.text('工作区 A'), findsOneWidget);
    expect(find.text('工作区 B'), findsOneWidget);
    expect(find.text('新建工作区'), findsOneWidget);
    expect(find.text('导入已有工作区'), findsOneWidget);
  });
}
