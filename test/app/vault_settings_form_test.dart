import 'package:encry_immortals_ui/app/theme.dart';
import 'package:encry_immortals_ui/app/widgets/vault_settings_form.dart';
import 'package:encry_immortals_ui/core/vault_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('普通/高级参数分组，并能读取修改后的值', (tester) async {
    AppColors.apply(Brightness.dark);
    addTearDown(() => AppColors.apply(Brightness.dark));
    final key = GlobalKey<VaultSettingsFormState>();
    VaultSettings latest = const VaultSettings();

    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: VaultSettingsForm(
              key: key,
              initial: const VaultSettings(),
              onChanged: (value) => latest = value,
            ),
          ),
        ),
      ),
    );

    expect(find.text('普通参数'), findsOneWidget);
    expect(find.text('高级参数'), findsOneWidget);
    expect(find.text('单次备份上限'), findsOneWidget);
    expect(find.text('排除规则（每行一条 glob，相对源目录）'), findsOneWidget);
    expect(find.text('pack 上限'), findsNothing);

    await tester.tap(find.text('高级参数'));
    await tester.pumpAndSettle();
    expect(find.text('pack 上限'), findsOneWidget);
    expect(find.text('暂存目录（可选）'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '单次备份上限'), '2048');
    await tester.pump();
    expect(latest.sessionMaxMib, 2048);

    expect(key.currentState!.validate(), isNull);

    await tester.enterText(find.widgetWithText(TextField, '单次备份上限'), '0');
    await tester.pump();
    expect(key.currentState!.validate(), isNotNull);
    await tester.pump();
    expect(find.text('参数不合法'), findsOneWidget);
  });

  testWidgets('恢复推荐值会重置字段', (tester) async {
    AppColors.apply(Brightness.dark);
    addTearDown(() => AppColors.apply(Brightness.dark));
    final key = GlobalKey<VaultSettingsFormState>();
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: VaultSettingsForm(
            key: key,
            initial: const VaultSettings(sessionMaxMib: 77, zstdLevel: 19),
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(key.currentState!.read().sessionMaxMib, 77);
    expect(key.currentState!.read().zstdLevel, 19);

    await tester.tap(find.text('恢复推荐值'));
    await tester.pumpAndSettle();
    final reset = key.currentState!.read();
    expect(reset.sessionMaxMib, 51200);
    expect(reset.zstdLevel, 5);
    expect(reset.validate(), isNull);
  });
}
