import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_paths.dart';
import 'private_file.dart';
import 'profile.dart';
import 'vault_config.dart';

class ProfileStoreException implements Exception {
  const ProfileStoreException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message（$cause）';
}

class ProfileStore {
  ProfileStore(this.paths);

  final AppPaths paths;

  Future<Profile?> load() async {
    final file = File(paths.profileFile);
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw ProfileStoreException('profile.json 不是合法 JSON。', error);
    }
    if (decoded is! Map) {
      throw const ProfileStoreException('profile.json 顶层必须是对象。');
    }
    final profile = Profile.fromJson(
      decoded.map((key, value) => MapEntry('$key', value)),
    );
    if (!File(profile.configPath).existsSync()) {
      throw ProfileStoreException('配置文件缺失：${profile.configPath}', null);
    }
    return profile;
  }

  Future<void> save(Profile profile) async {
    final tmp = File('${paths.profileFile}.tmp');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(profile.toJson()),
      flush: true,
    );
    await makePrivateFile(tmp.path);
    if (Platform.isWindows && await File(paths.profileFile).exists()) {
      await File(paths.profileFile).delete();
    }
    await tmp.rename(paths.profileFile);
  }

  Future<void> writeConfig(Profile profile) async {
    final config = VaultConfig(
      vaultDir: profile.vaultDir,
      targetDir: profile.targetDir,
      settings: profile.settings,
    );
    await config.writeTo(profile.configPath);
  }

  Future<void> saveWithConfig(Profile profile) async {
    await writeConfig(profile);
    await save(profile);
  }

  /// 只删除应用自己的配置/控制平面；**绝不删除 TargetDir**。
  Future<void> forget({bool deleteVault = true}) async {
    final profileFile = File(paths.profileFile);
    if (await profileFile.exists()) await profileFile.delete();
    final configFile = File(paths.configFile);
    if (await configFile.exists()) await configFile.delete();
    if (deleteVault) await deleteAppVault(paths.vaultDir);
  }

  Future<void> deleteAppVault(String vaultDir) async {
    final root = p.canonicalize(paths.root);
    final target = p.canonicalize(vaultDir);
    if (!p.isWithin(root, target)) {
      throw ProfileStoreException('拒绝删除不在应用数据目录内的 vault：$vaultDir');
    }
    final directory = Directory(target);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
