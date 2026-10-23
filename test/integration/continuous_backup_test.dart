@Tags(['integration'])
library;

import 'dart:io';

import 'package:encry_immortals_ui/app/backup_continuation.dart';
import 'package:encry_immortals_ui/core/app_paths.dart';
import 'package:encry_immortals_ui/core/command_queue.dart';
import 'package:encry_immortals_ui/core/core_models.dart';
import 'package:encry_immortals_ui/core/core_runtime.dart';
import 'package:encry_immortals_ui/core/onboarding_service.dart';
import 'package:encry_immortals_ui/core/profile_store.dart';
import 'package:encry_immortals_ui/core/vault_session.dart';
import 'package:encry_immortals_ui/core/vault_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final corePath = Platform.environment['EIMMORTAL_CORE_PATH'];
  final enabled =
      Platform.environment['RUN_CORE_INTEGRATION'] == '1' &&
      corePath != null &&
      corePath.isNotEmpty;

  test(
    '达到单次上限后，连续提交直到不再截断',
    () async {
      final root = await Directory.systemTemp.createTemp('eimmortal_cont_');
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final source = Directory(p.join(root.path, 'source'))..createSync();
      final target = Directory(p.join(root.path, 'target'))..createSync();
      for (var i = 0; i < 16; i++) {
        File(p.join(source.path, 'blob-$i.bin')).writeAsBytesSync(
          List<int>.generate(128 * 1024, (j) => (j + i) % 251),
        );
      }

      final paths = AppPaths(root: p.join(root.path, 'app'));
      await paths.ensure();
      final queue = CommandQueue();
      final runtime = await CoreRuntime.load(allowEnvironmentOverride: true);
      final onboarding = OnboardingService(
        gateway: runtime.gateway,
        paths: paths,
        store: ProfileStore(paths),
        queue: queue,
      );
      final created = await onboarding.create(
        sourceRoot: source.path,
        targetDir: target.path,
        password: 'continuous-check-password',
        settings: const VaultSettings(sessionMaxMib: 1, excludeRules: []),
      );
      expect(created.success, isTrue, reason: created.error);
      final session = VaultSession(
        gateway: runtime.gateway,
        profile: created.profile!,
        queue: queue,
      );
      final unlocked = await session.unlock('continuous-check-password');
      expect(unlocked.isSuccess, isTrue, reason: unlocked.errorSummary);

      int? previousSeq;
      var rounds = 0;
      BackupSummary? last;
      while (rounds < 10) {
        final result = await session.backup(message: 'continuous-test');
        expect(result.isSuccess, isTrue, reason: result.errorSummary);
        final summary = BackupSummary.fromJson(result.jsonMap!);
        last = summary;
        rounds++;
        if (!summary.truncated) break;
        expect(
          backupHasProgress(summary, previousSeq: previousSeq),
          isTrue,
          reason: '第 $rounds 轮没有推进',
        );
        previousSeq = summary.seq;
      }
      expect(last, isNotNull);
      expect(last!.truncated, isFalse);
      expect(rounds, greaterThan(1));
      queue.dispose();
    },
    skip: enabled ? false : '需要 RUN_CORE_INTEGRATION=1 与 EIMMORTAL_CORE_PATH',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
