import 'dart:io';

import 'package:encry_immortals_ui/core/vault_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('TOML 转义 Windows 反斜杠与引号', () {
    const config = VaultConfig(
      vaultDir: r'C:\Users\a"b\vault',
      targetDir: '/tmp/target',
      stagingDir: '/tmp/staging',
      ignoreXattr: true,
      sessionMaxMib: 512,
    );
    final toml = config.toToml();
    expect(toml, contains(r'dir = "C:\\Users\\a\"b\\vault"'));
    expect(toml, contains('target_dir = "/tmp/target"'));
    expect(toml, contains('staging_dir = "/tmp/staging"'));
    expect(toml, contains('session_max_mib = 512'));
    expect(toml, contains('ignore_xattr = true'));
    expect(toml, contains('[scan]'));
  });

  test('排除规则写成 TOML 数组', () {
    const config = VaultConfig(
      vaultDir: '/v',
      targetDir: '/t',
      exclude: ['*.tmp', 'node_modules/**'],
    );
    expect(
      config.toToml(),
      contains('exclude = ["*.tmp", "node_modules/**"]'),
    );
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
