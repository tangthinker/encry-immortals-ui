import 'dart:io';

import 'package:encry_immortals_ui/app/app_controller.dart';
import 'package:encry_immortals_ui/core/app_paths.dart';
import 'package:encry_immortals_ui/core/app_preferences.dart';
import 'package:encry_immortals_ui/core/core_gateway.dart';
import 'package:encry_immortals_ui/core/core_locator.dart';
import 'package:encry_immortals_ui/core/core_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../core/support/fake_core_process.dart';

void main() {
  late Directory temp;
  late AppPaths paths;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('eimmortal_controller_');
    paths = AppPaths(root: p.join(temp.path, 'app'));
    await paths.ensure();
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  CoreRuntime fakeRuntime() {
    final binary = CoreBinary(
      path: p.join(temp.path, 'eimmortal'),
      source: CoreBinarySource.development,
    );
    File(binary.path).writeAsStringSync('');
    return CoreRuntime(
      binary: binary,
      integrity: const CoreIntegrityResult(
        status: CoreIntegrityStatus.notPinned,
        actualSha256: 'deadbeef',
        expectedSha256: null,
      ),
      version: '0.1.0-dev',
      gateway: CoreGateway(
        binary: binary,
        launcher: FakeCoreLauncher(FakeCoreProcess()),
      ),
    );
  }

  test('没有 profile 时进入 onboarding', () async {
    final controller = AppController(
      paths: paths,
      runtimeLoader: () async => fakeRuntime(),
      acquireInstanceLock: false,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.phase, AppPhase.onboarding);
    expect(controller.coreVersion, '0.1.0-dev');
  });

  test('核心加载失败时进入 failed 并保留诊断', () async {
    final controller = AppController(
      paths: paths,
      runtimeLoader: () async =>
          throw const CoreRuntimeException('找不到 sidecar'),
      acquireInstanceLock: false,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.phase, AppPhase.failed);
    expect(controller.startupError, contains('sidecar'));
  });

  test('主题默认浅色，修改后跨控制器保留', () async {
    final first = AppController(
      paths: paths,
      runtimeLoader: () async => fakeRuntime(),
      acquireInstanceLock: false,
    );
    await first.initialize();
    expect(first.themeMode, AppThemeMode.light);
    await first.setThemeMode(AppThemeMode.dark);
    expect(first.themeMode, AppThemeMode.dark);
    expect(File(paths.preferencesFile).existsSync(), isTrue);
    first.dispose();

    final second = AppController(
      paths: paths,
      runtimeLoader: () async => fakeRuntime(),
      acquireInstanceLock: false,
    );
    addTearDown(second.dispose);
    await second.initialize();
    expect(second.themeMode, AppThemeMode.dark);
    await second.setThemeMode(AppThemeMode.system);
    expect(second.themeMode, AppThemeMode.system);
  });

  test('无工作区时创建草稿，取消新建回到 onboarding', () async {
    final controller = AppController(
      paths: paths,
      runtimeLoader: () async => fakeRuntime(),
      acquireInstanceLock: false,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.phase, AppPhase.onboarding);
    expect(controller.workspaces, isEmpty);
    expect(controller.hasDraftWorkspace, isTrue);

    await controller.beginWorkspaceSetup(WorkspaceSetupMode.create);
    expect(controller.phase, AppPhase.onboarding);
    expect(controller.workspaceSetupMode, WorkspaceSetupMode.create);

    await controller.cancelWorkspaceSetup();
    expect(controller.phase, AppPhase.onboarding);
    expect(controller.workspaceSetupMode, isNull);
    expect(controller.hasDraftWorkspace, isTrue);
    expect(controller.workspaces, isEmpty);
  });

  test('重置本地配置回到 onboarding', () async {
    final controller = AppController(
      paths: paths,
      runtimeLoader: () async => fakeRuntime(),
      acquireInstanceLock: false,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.resetLocalConfig();
    expect(controller.phase, AppPhase.onboarding);
    expect(File(paths.profileFile).existsSync(), isFalse);
  });
}
