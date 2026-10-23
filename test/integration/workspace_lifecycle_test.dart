@Tags(['integration'])
library;

import 'dart:io';

import 'package:encry_immortals_ui/app/app_controller.dart';
import 'package:encry_immortals_ui/core/app_paths.dart';
import 'package:encry_immortals_ui/core/command_queue.dart';
import 'package:encry_immortals_ui/core/core_runtime.dart';
import 'package:encry_immortals_ui/core/onboarding_service.dart';
import 'package:encry_immortals_ui/core/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final corePath = Platform.environment['EIMMORTAL_CORE_PATH'];
  final enabled =
      Platform.environment['RUN_CORE_INTEGRATION'] == '1' &&
      corePath != null &&
      corePath.isNotEmpty;

  test(
    '旧单工作区迁移、创建第二个工作区并切换',
    () async {
      final temp = await Directory.systemTemp.createTemp('eimmortal_ws_');
      addTearDown(() async {
        if (temp.existsSync()) await temp.delete(recursive: true);
      });
      final source = Directory(p.join(temp.path, 'source'))..createSync();
      File(p.join(source.path, 'a.txt')).writeAsStringSync('alpha\n');
      final targetA = Directory(p.join(temp.path, 'target-a'))..createSync();
      final targetB = Directory(p.join(temp.path, 'target-b'))..createSync();
      final root = AppPaths(root: p.join(temp.path, 'app'));
      await root.ensure();
      const password = 'workspace-integration-password';
      final runtime = await CoreRuntime.load(allowEnvironmentOverride: true);
      final queue = CommandQueue();

      // Write the old single-workspace layout at the app root first.
      final onboarding = OnboardingService(
        gateway: runtime.gateway,
        paths: root,
        store: ProfileStore(root),
        queue: queue,
      );
      final legacy = await onboarding.create(
        sourceRoot: source.path,
        targetDir: targetA.path,
        password: password,
      );
      expect(legacy.success, isTrue, reason: legacy.error);
      expect(File(root.profileFile).existsSync(), isTrue);

      final controller = AppController(
        paths: root,
        runtimeLoader: () async => runtime,
        acquireInstanceLock: false,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(controller.phase, AppPhase.locked);
      expect(controller.workspaces, hasLength(1));
      expect(File(root.profileFile).existsSync(), isFalse);
      final firstId = controller.activeWorkspace!.id;
      final firstProfile = controller.profile!;
      expect(firstProfile.vaultDir, startsWith(root.workspacesDir));
      expect(firstProfile.configPath, startsWith(root.workspacesDir));

      final unlocked = await controller.unlock(password);
      expect(unlocked.success, isTrue, reason: unlocked.message);
      expect(controller.phase, AppPhase.unlocked);

      await controller.beginWorkspaceSetup(WorkspaceSetupMode.create);
      expect(controller.phase, AppPhase.onboarding);
      final second = await controller.createVault(
        sourceRoot: source.path,
        targetDir: targetB.path,
        password: password,
      );
      expect(second.success, isTrue, reason: second.error);
      final activated = await controller.activateProfile(
        second.profile!,
        password,
      );
      expect(activated.success, isTrue, reason: activated.message);
      expect(controller.phase, AppPhase.unlocked);
      expect(controller.workspaces, hasLength(2));
      final secondId = controller.activeWorkspace!.id;
      expect(secondId, isNot(firstId));

      final switched = await controller.switchWorkspace(firstId);
      expect(switched, isNull);
      expect(controller.phase, AppPhase.locked);
      expect(controller.activeWorkspace!.id, firstId);
      expect(controller.profile!.configPath, firstProfile.configPath);

      final switchedBack = await controller.switchWorkspace(secondId);
      expect(switchedBack, isNull);
      expect(controller.activeWorkspace!.id, secondId);
      queue.dispose();
    },
    skip: enabled ? false : '需要 RUN_CORE_INTEGRATION=1 与 EIMMORTAL_CORE_PATH',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
