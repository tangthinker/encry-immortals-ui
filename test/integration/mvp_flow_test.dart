@Tags(['integration'])
library;

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:encry_immortals_ui/app/app_controller.dart';
import 'package:encry_immortals_ui/core/app_paths.dart';
import 'package:encry_immortals_ui/core/command_queue.dart';
import 'package:encry_immortals_ui/core/core_models.dart';
import 'package:encry_immortals_ui/core/core_runtime.dart';
import 'package:encry_immortals_ui/core/onboarding_service.dart';
import 'package:encry_immortals_ui/core/profile_store.dart';
import 'package:encry_immortals_ui/core/vault_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final corePath = Platform.environment['EIMMORTAL_CORE_PATH'];
  final enabled =
      Platform.environment['RUN_CORE_INTEGRATION'] == '1' &&
      corePath != null &&
      corePath.isNotEmpty;

  test(
    '创建库 → 备份 → 历史 → 恢复 → 校验 → 加入库',
    () async {
      final root = await Directory.systemTemp.createTemp('eimmortal_mvp_');
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final queue = CommandQueue();
      final runtime = await CoreRuntime.load(allowEnvironmentOverride: true);
      final password = 'test-password-${DateTime.now().microsecondsSinceEpoch}';

      final source = Directory(p.join(root.path, 'source'))
        ..createSync(recursive: true);
      final target = Directory(p.join(root.path, 'target'))
        ..createSync(recursive: true);
      File(p.join(source.path, 'a.txt')).writeAsStringSync('alpha\n');
      Directory(p.join(source.path, 'sub')).createSync();
      File(p.join(source.path, 'sub', 'b.txt')).writeAsStringSync('beta\n');
      File(p.join(source.path, 'sub', 'binary.bin')).writeAsBytesSync(
        List<int>.generate(256 * 1024, (index) => index % 251),
      );

      final appA = AppPaths(root: p.join(root.path, 'appA'));
      await appA.ensure();
      final storeA = ProfileStore(appA);
      final onboardingA = OnboardingService(
        gateway: runtime.gateway,
        paths: appA,
        store: storeA,
        queue: queue,
      );

      final created = await onboardingA.create(
        sourceRoot: source.path,
        targetDir: target.path,
        password: password,
        onLog: (line) => print('[create] $line'),
      );
      expect(created.success, isTrue, reason: created.error);
      expect(created.profile, isNotNull);
      expect(created.key, isNotNull);
      expect(created.key!.armor, startsWith('EIMMORTAL-KEY-V2-'));
      expect(File(appA.profileFile).existsSync(), isTrue);

      final sessionA = VaultSession(
        gateway: runtime.gateway,
        profile: created.profile!,
        queue: queue,
      );
      final unlock = await sessionA.unlock(password);
      expect(unlock.isSuccess, isTrue, reason: unlock.errorSummary);

      final backup = await sessionA.backup(message: 'integration');
      expect(backup.isSuccess, isTrue, reason: backup.errorSummary);
      final summary = BackupSummary.fromJson(backup.jsonMap!);
      expect(summary.changed, isTrue);
      expect(summary.seq, greaterThanOrEqualTo(1));

      final history = await sessionA.history();
      expect(history.isSuccess, isTrue);
      final commits = history.jsonList!
          .map((item) => CommitEntry.fromJson(asJsonMap(item)))
          .toList();
      expect(commits.any((commit) => commit.seq == summary.seq), isTrue);

      final show = await sessionA.show(summary.seq);
      expect(show.isSuccess, isTrue, reason: show.errorSummary);
      final detail = CommitDetail.fromJson(show.jsonMap!);
      expect(detail.ops, isNotEmpty);
      expect(detail.ops.any((op) => op.path.endsWith('a.txt')), isTrue);

      final ls = await sessionA.listSnapshot(summary.seq);
      expect(ls.isSuccess, isTrue, reason: ls.errorSummary);
      final files = ls.jsonList!
          .map((item) => FileEntry.fromJson(asJsonMap(item)))
          .toList();
      expect(files.any((file) => file.path == 'a.txt'), isTrue);
      expect(files.any((file) => file.path == 'sub'), isTrue);

      final chain = await sessionA.status(chain: true);
      expect(chain.isSuccess, isTrue);
      final status = VaultStatus.fromJson(chain.jsonMap!);
      expect(status.hasUnlockWarning, isFalse);
      expect(status.referencedPacks, greaterThanOrEqualTo(1));

      final doctor = await sessionA.doctor(chain: true);
      expect(doctor.isSuccess, isTrue, reason: doctor.errorSummary);
      final checks = doctor.jsonList!
          .map((item) => DoctorCheck.fromJson(asJsonMap(item)))
          .toList();
      expect(checks.any((check) => check.status.isBlocking), isFalse);

      final packs = await sessionA.restore(
        destination: '',
        seq: summary.seq,
        listPacks: true,
      );
      expect(packs.isSuccess, isTrue, reason: packs.errorSummary);
      final packList = packs.jsonList!
          .map((item) => PackRef.fromJson(asJsonMap(item)))
          .toList();
      expect(packList, isNotEmpty);
      expect(packList.every((pack) => pack.present), isTrue);

      final restored = Directory(p.join(root.path, 'restoredA'));
      final restore = await sessionA.restore(
        destination: restored.path,
        seq: summary.seq,
      );
      expect(restore.isSuccess, isTrue, reason: restore.errorSummary);
      final restoredSummary = RestoreSummary.fromJson(restore.jsonMap!);
      expect(restoredSummary.incomplete, isFalse);
      expect(
        File(p.join(restored.path, 'sub', 'b.txt')).readAsStringSync(),
        'beta\n',
      );
      expect(
        File(p.join(restored.path, 'sub', 'binary.bin')).lengthSync(),
        256 * 1024,
      );

      final verify = await sessionA.verify(sample: 1);
      expect(verify.isSuccess, isTrue, reason: verify.errorSummary);
      expect(VerifySummary.fromJson(verify.jsonMap!).isClean, isTrue);

      final exported = await sessionA.exportKey();
      expect(exported.isSuccess, isTrue);
      final key = exportKeyFromResult(exported);
      expect(key, isNotNull);
      expect(key!.armor, startsWith('EIMMORTAL-KEY-V2-'));

      // 第二台“机器”：独立应用目录，用 Armor Key 加入同一个 TargetDir。
      final appB = AppPaths(root: p.join(root.path, 'appB'));
      await appB.ensure();
      final storeB = ProfileStore(appB);
      final onboardingB = OnboardingService(
        gateway: runtime.gateway,
        paths: appB,
        store: storeB,
        queue: queue,
      );
      final joined = await onboardingB.join(
        sourceRoot: source.path,
        targetDir: target.path,
        armorKey: key.armor,
        password: password,
        onLog: (line) => print('[join] $line'),
      );
      expect(joined.success, isTrue, reason: joined.error);
      expect(joined.profile, isNotNull);
      expect(joined.profile!.mode.name, 'joined');

      final sessionB = VaultSession(
        gateway: runtime.gateway,
        profile: joined.profile!,
        queue: queue,
      );
      final unlockB = await sessionB.unlock(password);
      expect(unlockB.isSuccess, isTrue, reason: unlockB.errorSummary);

      final chainB = await sessionB.status(chain: true);
      expect(chainB.isSuccess, isTrue);
      expect(VaultStatus.fromJson(chainB.jsonMap!).referencedPacks, greaterThanOrEqualTo(1));

      final restoredB = Directory(p.join(root.path, 'restoredB'));
      final restoreB = await sessionB.restore(
        destination: restoredB.path,
        seq: summary.seq,
      );
      expect(restoreB.isSuccess, isTrue, reason: restoreB.errorSummary);
      expect(
        File(p.join(restoredB.path, 'a.txt')).readAsStringSync(),
        'alpha\n',
      );

      final secondBackup = await sessionB.backup(message: 'from second client');
      expect(secondBackup.isSuccess, isTrue, reason: secondBackup.errorSummary);

      queue.dispose();
    },
    skip: enabled ? false : '需要 RUN_CORE_INTEGRATION=1 与 EIMMORTAL_CORE_PATH',
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'AppController：创建 → 激活 → 锁定 → 解锁 → 修改 session 上限',
    () async {
      final root = await Directory.systemTemp.createTemp('eimmortal_controller_it_');
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final source = Directory(p.join(root.path, 'source'))
        ..createSync(recursive: true);
      final target = Directory(p.join(root.path, 'target'))
        ..createSync(recursive: true);
      File(p.join(source.path, 'a.txt')).writeAsStringSync('alpha\n');
      final paths = AppPaths(root: p.join(root.path, 'app'));
      await paths.ensure();
      final runtime = await CoreRuntime.load(allowEnvironmentOverride: true);
      final controller = AppController(
        paths: paths,
        profileStore: ProfileStore(paths),
        runtimeLoader: () async => runtime,
        acquireInstanceLock: false,
      );
      addTearDown(controller.dispose);
      const password = 'integration-password-2026';

      await controller.initialize();
      expect(controller.phase, AppPhase.onboarding);
      final created = await controller.createVault(
        sourceRoot: source.path,
        targetDir: target.path,
        password: password,
      );
      expect(created.success, isTrue, reason: created.error);
      final activated = await controller.activateProfile(
        created.profile!,
        password,
      );
      expect(activated.success, isTrue, reason: activated.message);
      expect(controller.phase, AppPhase.unlocked);

      expect(controller.lock(), isTrue);
      expect(controller.phase, AppPhase.locked);
      final unlocked = await controller.unlock(password);
      expect(unlocked.success, isTrue, reason: unlocked.message);
      expect(controller.phase, AppPhase.unlocked);

      await controller.updateSessionLimit(2048);
      final profile = await ProfileStore(paths).load();
      expect(profile?.sessionMaxMib, 2048);
      final config = File(paths.configFile).readAsStringSync();
      expect(config, contains('session_max_mib = 2048'));
      expect(controller.session?.profile.sessionMaxMib, 2048);
    },
    skip: enabled ? false : '需要 RUN_CORE_INTEGRATION=1 与 EIMMORTAL_CORE_PATH',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
