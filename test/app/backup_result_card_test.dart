import 'package:encry_immortals_ui/app/screens/backup_page.dart';
import 'package:encry_immortals_ui/app/theme.dart';
import 'package:encry_immortals_ui/core/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BackupSummary summary({bool truncated = true}) {
  return BackupSummary(
    seq: 7,
    changed: true,
    dryRun: false,
    added: 12,
    modified: 3,
    deleted: 1,
    meta: 0,
    dirs: 2,
    links: 0,
    plainBytes: 1024 * 1024,
    packBytes: 512 * 1024,
    journalBytes: 4096,
    manifests: 2,
    truncated: truncated,
    skipped: 0,
  );
}

Future<void> pumpCard(
  WidgetTester tester, {
  required BackupSummary data,
  required bool dryRun,
  required VoidCallback onContinue,
  required VoidCallback onContinuous,
  int continuousCommits = 0,
  bool continuousStopped = false,
  bool continuousNoProgress = false,
  bool continuousLimitReached = false,
}) async {
  AppColors.apply(Brightness.light);
  await tester.binding.setSurfaceSize(const Size(900, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: BackupResultCard(
            summary: data,
            dryRun: dryRun,
            onContinue: onContinue,
            onContinuous: onContinuous,
            continuousCommits: continuousCommits,
            continuousStopped: continuousStopped,
            continuousNoProgress: continuousNoProgress,
            continuousLimitReached: continuousLimitReached,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('截断结果同时提供继续备份和持续备份', (tester) async {
    var continueCount = 0;
    var continuousCount = 0;
    await pumpCard(
      tester,
      data: summary(),
      dryRun: false,
      onContinue: () => continueCount++,
      onContinuous: () => continuousCount++,
    );

    expect(find.text('继续备份'), findsOneWidget);
    expect(find.text('持续备份到所有数据备份完毕'), findsOneWidget);

    await tester.tap(find.text('继续备份'));
    await tester.tap(find.text('持续备份到所有数据备份完毕'));
    expect(continueCount, 1);
    expect(continuousCount, 1);
  });

  testWidgets('持续备份完成后不显示继续按钮', (tester) async {
    await pumpCard(
      tester,
      data: summary(truncated: false),
      dryRun: false,
      onContinue: () {},
      onContinuous: () {},
      continuousCommits: 4,
    );

    expect(find.text('持续备份完成'), findsOneWidget);
    expect(find.text('共完成 4 次提交；剩余数据已全部处理'), findsOneWidget);
    expect(find.text('继续备份'), findsNothing);
    expect(find.text('持续备份到所有数据备份完毕'), findsNothing);
  });

  testWidgets('预演截断只保留继续备份', (tester) async {
    await pumpCard(
      tester,
      data: summary(),
      dryRun: true,
      onContinue: () {},
      onContinuous: () {},
    );

    expect(find.text('继续备份'), findsOneWidget);
    expect(find.text('持续备份到所有数据备份完毕'), findsNothing);
  });

  testWidgets('停止后的持续备份保留两个操作和剩余提示', (tester) async {
    await pumpCard(
      tester,
      data: summary(),
      dryRun: false,
      onContinue: () {},
      onContinuous: () {},
      continuousCommits: 2,
      continuousStopped: true,
    );

    expect(find.text('持续备份已暂停'), findsOneWidget);
    expect(find.text('继续备份'), findsOneWidget);
    expect(find.text('持续备份到所有数据备份完毕'), findsOneWidget);
    expect(find.textContaining('仍有剩余数据'), findsWidgets);
  });
}
