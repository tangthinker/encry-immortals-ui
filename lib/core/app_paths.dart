import 'dart:io';

import 'package:path/path.dart' as p;

import 'private_file.dart';

/// 应用自己的数据目录。控制平面（vault.meta/state.db/journal）也放在这里，
/// 与用户选择的 TargetDir 分离；CLI 的 `~/.eimmortal` 不会被改写。
///
/// - macOS: ~/Library/Application Support/EncryImmortals
/// - Windows: %APPDATA%\EncryImmortals
/// - 其他: $XDG_CONFIG_HOME/encry-immortals 或 ~/.config/encry-immortals
class AppPaths {
  const AppPaths({required this.root});

  final String root;

  static AppPaths resolve({
    Map<String, String>? environment,
    String? operatingSystem,
  }) {
    final env = environment ?? Platform.environment;
    final os = operatingSystem ?? Platform.operatingSystem;
    final home = env['HOME'] ?? env['USERPROFILE'];
    if (home == null || home.isEmpty) {
      throw StateError('无法确定用户主目录。');
    }

    final context = p.Context(
      style: os == 'windows' ? p.Style.windows : p.Style.posix,
    );
    final String root;
    if (os == 'macos') {
      root = context.join(
        home,
        'Library',
        'Application Support',
        'EncryImmortals',
      );
    } else if (os == 'windows') {
      final appData = env['APPDATA'];
      root = appData != null && appData.isNotEmpty
          ? context.join(appData, 'EncryImmortals')
          : context.join(home, 'AppData', 'Roaming', 'EncryImmortals');
    } else {
      final xdg = env['XDG_CONFIG_HOME'];
      root = xdg != null && xdg.isNotEmpty
          ? context.join(xdg, 'encry-immortals')
          : context.join(home, '.config', 'encry-immortals');
    }
    return AppPaths(root: root);
  }

  /// Legacy single-workspace locations. New workspaces live under
  /// `workspaces/<id>/`; these getters remain for migration and tests.
  String get profileFile => p.join(root, 'profile.json');
  String get configFile => p.join(root, 'config.toml');
  String get vaultDir => p.join(root, 'vault');
  String get instanceLockFile => p.join(root, 'instance.lock');
  String get preferencesFile => p.join(root, 'preferences.json');

  String get workspacesDir => p.join(root, 'workspaces');
  String get workspacesIndexFile => p.join(root, 'workspaces.json');
  String workspaceDir(String id) => p.join(workspacesDir, id);
  AppPaths workspacePaths(String id) => AppPaths(root: workspaceDir(id));

  Directory get directory => Directory(root);
  Directory get vaultDirectory => Directory(vaultDir);

  Future<void> ensure() async {
    await directory.create(recursive: true);
    await makePrivateDirectory(root);
  }
}
