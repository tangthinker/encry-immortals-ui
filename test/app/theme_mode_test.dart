import 'package:encry_immortals_ui/app.dart';
import 'package:encry_immortals_ui/core/app_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_app.dart';

void main() {
  testWidgets('默认浅色，可切深色与跟随系统', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(() {
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    });
    final app = (await tester.runAsync(FakeApp.create))!;
    addTearDown(() async {
      await app.dispose();
    });
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(EncryImmortalsApp(controller: app.controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    MaterialApp materialApp() => tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );

    expect(app.controller.themeMode, AppThemeMode.light);
    expect(materialApp().theme?.brightness, Brightness.light);

    await tester.runAsync(() => app.controller.setThemeMode(AppThemeMode.dark));
    await tester.pump();
    expect(materialApp().theme?.brightness, Brightness.dark);

    await tester.runAsync(() => app.controller.setThemeMode(AppThemeMode.system));
    await tester.pump();
    expect(materialApp().theme?.brightness, Brightness.light);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    expect(materialApp().theme?.brightness, Brightness.dark);
  });
}
