import 'dart:io';

import 'package:encry_immortals_ui/core/vault_config.dart';
import 'package:encry_immortals_ui/core/vault_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('TOML 转义与全部参数', () {
    const config = VaultConfig(
      vaultDir: r'C:\Users\a"b\vault',
      targetDir: '/tmp/target',
      settings: VaultSettings(
        stagingDir: '/tmp/staging',
        sessionMaxMib: 512,
        packMaxMiB: 256,
        slicePlainMiB: 16,
        smallFileMiB: 100,
        zstdLevel: 9,
        minCompressKiB: 8,
        scanMode: 'strict',
        excludeRules: ['*.tmp', 'node_modules/**'],
        followHardlinks: 'split',
        ignoreXattr: false,
        sparseMaxMiB: 2,
        onChangeStrategy: 'skip',
      ),
    );
    final toml = config.toToml();
    expect(toml, contains(r'dir = "C:\\Users\\a\"b\\vault"'));
    expect(toml, contains('target_dir = "/tmp/target"'));
    expect(toml, contains('staging_dir = "/tmp/staging"'));
    expect(toml, contains('pack_max_bytes = 268435456'));
    expect(toml, contains('slice_plain_bytes = 16777216'));
    expect(toml, contains('small_file_bytes = 104857600'));
    expect(toml, contains('session_max_mib = 512'));
    expect(toml, contains('zstd_level = 9'));
    expect(toml, contains('min_compress_bytes = 8192'));
    expect(toml, contains('mode = "strict"'));
    expect(toml, contains('exclude = ["*.tmp", "node_modules/**"]'));
    expect(toml, contains('follow_hardlinks = "split"'));
    expect(toml, contains('ignore_xattr = false'));
    expect(toml, contains('sparse_max_bytes = 2097152'));
    expect(toml, contains('strategy = "skip"'));
  });

  test('空 exclude 也显式写出，表示关闭默认排除', () {
    const config = VaultConfig(
      vaultDir: '/v',
      targetDir: '/t',
      settings: VaultSettings(excludeRules: []),
    );
    expect(config.toToml(), contains('exclude = []'));
  });

  test('非法参数拒绝生成配置', () {
    const config = VaultConfig(
      vaultDir: '/v',
      targetDir: '/t',
      settings: VaultSettings(packMaxMiB: 8, slicePlainMiB: 16),
    );
    expect(config.toToml, throwsArgumentError);
  });

  test('路径含换行时拒绝生成配置', () {
    const config = VaultConfig(vaultDir: '/tmp/a\nb', targetDir: '/tmp/t');
    expect(config.toToml, throwsArgumentError);
  });

  test('POSIX 上配置文件权限为 0600', () async {
    final dir = await Directory.systemTemp.createTemp('eimmortal_config_test_');
    addTearDown(() => dir.delete(recursive: true));
    const config = VaultConfig(vaultDir: '/v', targetDir: '/t');
    final file = await config.writeTo(p.join(dir.path, 'config.toml'));
    expect(await file.exists(), isTrue);
    if (!Platform.isWindows) {
      final mode = file.statSync().mode & 0x1FF;
      expect(mode, 0x180, reason: '0600 = 0x180');
    }
  });
}
