import 'dart:io';

import 'package:encry_immortals_ui/core/app_paths.dart';
import 'package:encry_immortals_ui/core/profile.dart';
import 'package:encry_immortals_ui/core/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late AppPaths paths;
  late ProfileStore store;
  late Profile profile;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('eimmortal_profile_');
    paths = AppPaths(root: p.join(temp.path, 'app'));
    await paths.ensure();
    await Directory(paths.vaultDir).create(recursive: true);
    await File(p.join(paths.vaultDir, 'vault.meta')).writeAsString('{}');
    store = ProfileStore(paths);
    profile = Profile(
      id: 'p1',
      name: 'backup',
      vaultDir: paths.vaultDir,
      targetDir: p.join(temp.path, 'target'),
      configPath: paths.configFile,
      sourceRoot: p.join(temp.path, 'source'),
      mode: ProfileMode.created,
      createdAt: DateTime.now(),
    );
    await Directory(profile.targetDir).create(recursive: true);
    await File(p.join(profile.targetDir, 'keep.txt')).writeAsString('keep');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('保存并读取 profile，配置权限为 0600', () async {
    await store.saveWithConfig(profile);
    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.id, profile.id);
    expect(loaded.targetDir, profile.targetDir);
    expect(File(paths.configFile).existsSync(), isTrue);
    expect(File(paths.profileFile).existsSync(), isTrue);
    if (!Platform.isWindows) {
      expect(File(paths.configFile).statSync().mode & 0x1FF, 0x180);
      expect(File(paths.profileFile).statSync().mode & 0x1FF, 0x180);
    }
  });

  test('配置缺失时 load 报可诊断错误', () async {
    await store.saveWithConfig(profile);
    await File(paths.configFile).delete();
    await expectLater(
      store.load(),
      throwsA(isA<ProfileStoreException>()),
    );
  });

  test('forget 删除本地 vault，但绝不删除 TargetDir', () async {
    await store.saveWithConfig(profile);
    await store.forget(deleteVault: true);
    expect(File(paths.profileFile).existsSync(), isFalse);
    expect(File(paths.configFile).existsSync(), isFalse);
    expect(Directory(paths.vaultDir).existsSync(), isFalse);
    expect(File(p.join(profile.targetDir, 'keep.txt')).existsSync(), isTrue);
  });

  test('deleteAppVault 拒绝删除应用目录之外的数据', () async {
    expect(
      () => store.deleteAppVault(profile.targetDir),
      throwsA(isA<ProfileStoreException>()),
    );
    expect(File(p.join(profile.targetDir, 'keep.txt')).existsSync(), isTrue);
  });
}
