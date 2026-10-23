import 'dart:io';

import 'package:encry_immortals_ui/app/app_controller.dart';
import 'package:encry_immortals_ui/core/app_paths.dart';
import 'package:encry_immortals_ui/core/core_gateway.dart';
import 'package:encry_immortals_ui/core/core_locator.dart';
import 'package:encry_immortals_ui/core/core_runtime.dart';
import 'package:path/path.dart' as p;

import '../../core/support/fake_core_process.dart';

class FakeApp {
  FakeApp._(this.temp, this.paths, this.controller);

  final Directory temp;
  final AppPaths paths;
  final AppController controller;

  static Future<FakeApp> create({bool initialize = true}) async {
    final temp = await Directory.systemTemp.createTemp('eimmortal_app_test_');
    final paths = AppPaths(root: p.join(temp.path, 'app'));
    await paths.ensure();
    final binary = CoreBinary(
      path: p.join(temp.path, 'eimmortal'),
      source: CoreBinarySource.development,
    );
    File(binary.path).writeAsStringSync('');
    final runtime = CoreRuntime(
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
    final controller = AppController(
      paths: paths,
      runtimeLoader: () async => runtime,
      acquireInstanceLock: false,
    );
    if (initialize) await controller.initialize();
    return FakeApp._(temp, paths, controller);
  }

  Future<void> dispose() async {
    controller.dispose();
    if (temp.existsSync()) await temp.delete(recursive: true);
  }
}
