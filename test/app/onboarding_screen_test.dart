import 'dart:io';

import 'package:encry_immortals_ui/app.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_app.dart';

import 'package:encry_immortals_ui/app/theme.dart';

void main() {
  testWidgets('无 profile 时显示 onboarding 选择页', (tester) async {
    final app = (await tester.runAsync(FakeApp.create))!;
    addTearDown(() {
      app.controller.dispose();
      if (app.temp.existsSync()) app.temp.deleteSync(recursive: true);
    });
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(EncryImmortalsApp(controller: app.controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('选择如何开始'), findsOneWidget);
    expect(find.text('创建新库'), findsOneWidget);
    expect(find.text('加入已有库'), findsOneWidget);
  });

  testWidgets('浅色外观下 onboarding 可渲染', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(() {
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      AppColors.apply(Brightness.dark);
    });
    final app = (await tester.runAsync(FakeApp.create))!;
    addTearDown(() {
      app.controller.dispose();
      if (app.temp.existsSync()) app.temp.deleteSync(recursive: true);
    });
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(EncryImmortalsApp(controller: app.controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('选择如何开始'), findsOneWidget);
    expect(find.text('创建新库'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('创建向导在未选目录时阻止继续', (tester) async {
    final app = (await tester.runAsync(FakeApp.create))!;
    addTearDown(() {
      app.controller.dispose();
      if (app.temp.existsSync()) app.temp.deleteSync(recursive: true);
    });
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(EncryImmortalsApp(controller: app.controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('创建新库'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('源目录'), findsOneWidget);
    expect(find.text('TargetDir'), findsOneWidget);

    await tester.tap(find.text('继续'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('请选择要备份的源目录'), findsOneWidget);
  });

  _onboardingParameterStepTests();
}

class _FakeDirectorySelector extends FileSelectorPlatform {
  _FakeDirectorySelector(this.paths);

  final List<String> paths;
  int _index = 0;

  @override
  Future<String?> getDirectoryPathWithOptions(FileDialogOptions options) async {
    return paths[_index++ % paths.length];
  }
}

void _onboardingParameterStepTests() {
  testWidgets('创建向导包含普通/高级参数页并可校验', (tester) async {
    final original = FileSelectorPlatform.instance;
    addTearDown(() => FileSelectorPlatform.instance = original);
    final app = (await tester.runAsync(FakeApp.create))!;
    addTearDown(() async {
      await app.dispose();
      if (app.temp.existsSync()) app.temp.deleteSync(recursive: true);
    });
    final source = Directory(p.join(app.temp.path, 'source'))..createSync();
    final target = Directory(p.join(app.temp.path, 'target'))..createSync();
    FileSelectorPlatform.instance = _FakeDirectorySelector([
      source.path,
      target.path,
    ]);

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(EncryImmortalsApp(controller: app.controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('创建新库'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('选择…').at(0));
    await tester.pump();
    await tester.tap(find.text('选择…').at(1));
    await tester.pump();
    await tester.ensureVisible(find.text('继续'));
    await tester.tap(find.text('继续'));
    await tester.pump();

    await tester.enterText(
      find.byType(TextField).at(0),
      'a-strong-password-2026',
    );
    await tester.enterText(
      find.byType(TextField).at(1),
      'a-strong-password-2026',
    );
    await tester.ensureVisible(find.text('继续'));
    await tester.tap(find.text('继续'));
    await tester.pump();

    expect(find.text('普通参数'), findsOneWidget);
    expect(find.text('高级参数'), findsOneWidget);
    expect(find.text('排除规则（每行一条 glob，相对源目录）'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '单次备份上限'), '512');
    await tester.ensureVisible(find.text('高级参数'));
    await tester.tap(find.text('高级参数'));
    await tester.pumpAndSettle();
    expect(find.text('pack 上限'), findsOneWidget);

    await tester.ensureVisible(find.text('继续'));
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('创建备份库'), findsOneWidget);
    expect(find.textContaining('上限 512 MiB'), findsOneWidget);
  });
}
