import 'dart:io';

import 'package:encry_immortals_ui/core/app_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析 macOS 应用目录', () {
    final paths = AppPaths.resolve(
      environment: {'HOME': '/Users/alice'},
      operatingSystem: 'macos',
    );
    expect(
      paths.root,
      '/Users/alice/Library/Application Support/EncryImmortals',
    );
    expect(paths.profileFile, endsWith('profile.json'));
    expect(paths.configFile, endsWith('config.toml'));
    expect(paths.vaultDir, endsWith('vault'));
  });

  test('解析 Windows 应用目录', () {
    final paths = AppPaths.resolve(
      environment: {
        'USERPROFILE': r'C:\Users\alice',
        'APPDATA': r'C:\Users\alice\AppData\Roaming',
      },
      operatingSystem: 'windows',
    );
    expect(paths.root, r'C:\Users\alice\AppData\Roaming\EncryImmortals');
  });

  test('解析 Linux 应用目录', () {
    final paths = AppPaths.resolve(
      environment: {
        'HOME': '/home/alice',
        'XDG_CONFIG_HOME': '/home/alice/.config',
      },
      operatingSystem: 'linux',
    );
    expect(paths.root, '/home/alice/.config/encry-immortals');
  });

  test('ensure 创建私有目录', () async {
    final temp = await Directory.systemTemp.createTemp('eimmortal_paths_');
    addTearDown(() => temp.delete(recursive: true));
    final root = '${temp.path}/app';
    final paths = AppPaths(root: root);
    await paths.ensure();
    expect(Directory(root).existsSync(), isTrue);
    if (!Platform.isWindows) {
      expect(Directory(root).statSync().mode & 0x1FF, 0x1C0);
    }
  });
}
