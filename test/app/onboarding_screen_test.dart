import 'package:encry_immortals_ui/app.dart';
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
}
