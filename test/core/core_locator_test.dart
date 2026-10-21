import 'dart:io';

import 'package:encry_immortals_ui/core/core_locator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('eimmortal_locator_');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('从 macOS app bundle 解析 sidecar', () async {
    final app = p.join(temp.path, 'Encry Immortals.app');
    final executable = p.join(app, 'Contents', 'MacOS', 'Encry Immortals');
    final sidecar = p.join(app, 'Contents', 'Resources', 'bin', 'eimmortal');
    File(executable).createSync(recursive: true);
    File(sidecar).createSync(recursive: true);

    final binary = CoreLocator(
      resolvedExecutable: executable,
      environment: const {},
      operatingSystem: 'macos',
      allowEnvironmentOverride: false,
    ).locate();

    expect(binary.path, p.absolute(sidecar));
    expect(binary.source, CoreBinarySource.bundle);
  });

  test('Windows 优先找 GUI 子系统 sidecar', () async {
    final install = p.join(temp.path, 'install');
    final executable = p.join(install, 'Encry Immortals.exe');
    final gui = p.join(install, 'bin', 'eimmortal-gui.exe');
    File(executable).createSync(recursive: true);
    File(gui).createSync(recursive: true);

    final binary = CoreLocator(
      resolvedExecutable: executable,
      environment: const {},
      operatingSystem: 'windows',
      allowEnvironmentOverride: false,
    ).locate();

    expect(binary.path, p.absolute(gui));
    expect(binary.source, CoreBinarySource.bundle);
  });

  test('release 忽略 EIMMORTAL_CORE_PATH，debug 允许覆盖', () async {
    final custom = p.join(temp.path, 'custom');
    File(custom).createSync(recursive: true);
    final locator = CoreLocator(
      resolvedExecutable: p.join(temp.path, 'missing.exe'),
      environment: {'EIMMORTAL_CORE_PATH': custom},
      operatingSystem: 'macos',
      allowEnvironmentOverride: true,
    );
    expect(locator.locate().path, p.absolute(custom));

    final releaseLocator = CoreLocator(
      resolvedExecutable: p.join(temp.path, 'missing.exe'),
      environment: {'EIMMORTAL_CORE_PATH': custom},
      operatingSystem: 'macos',
      allowEnvironmentOverride: false,
    );
    expect(
      () => releaseLocator.locate(),
      throwsA(isA<CoreBinaryNotFound>()),
    );
  });
}
