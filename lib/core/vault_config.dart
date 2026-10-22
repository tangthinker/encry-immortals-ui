import 'dart:io';

import 'package:path/path.dart' as p;

import 'vault_settings.dart';

/// GUI 维护的 `config.toml`。
///
/// 只写白名单字段，不接管用户已有的完整配置；字段语义见核心
/// `config.example.toml`。POSIX 上必须落成 0600，否则 CLI 以 E2 拒绝启动。
class VaultConfig {
  const VaultConfig({
    required this.vaultDir,
    required this.targetDir,
    this.settings = const VaultSettings(),
  });

  final String vaultDir;
  final String targetDir;
  final VaultSettings settings;

  String toToml() {
    final error = settings.validate();
    if (error != null) {
      throw ArgumentError(error);
    }
    final buffer = StringBuffer()
      ..writeln('[vault]')
      ..writeln('dir = "${_escape(vaultDir)}"')
      ..writeln()
      ..writeln('[storage]')
      ..writeln('target_dir = "${_escape(targetDir)}"');
    if (settings.stagingDir.trim().isNotEmpty) {
      buffer.writeln('staging_dir = "${_escape(settings.stagingDir.trim())}"');
    }
    buffer
      ..writeln('pack_max_bytes = ${settings.packMaxBytes}')
      ..writeln('slice_plain_bytes = ${settings.slicePlainBytes}')
      ..writeln('small_file_bytes = ${settings.smallFileBytes}')
      ..writeln('session_max_mib = ${settings.sessionMaxMib}')
      ..writeln()
      ..writeln('[codec]')
      ..writeln('zstd_level = ${settings.zstdLevel}')
      ..writeln('min_compress_bytes = ${settings.minCompressBytes}')
      ..writeln()
      ..writeln('[scan]')
      ..writeln('mode = "${_escape(settings.scanMode)}"')
      ..write('exclude = [')
      ..write(
        settings.excludeRules
            .map((rule) => '"${_escape(rule.trim())}"')
            .join(', '),
      )
      ..writeln(']')
      ..writeln('follow_hardlinks = "${_escape(settings.followHardlinks)}"')
      ..writeln('ignore_xattr = ${settings.ignoreXattr}')
      ..writeln('sparse_max_bytes = ${settings.sparseMaxBytes}')
      ..writeln()
      ..writeln('[on_change_during_read]')
      ..writeln('strategy = "${_escape(settings.onChangeStrategy)}"');
    return buffer.toString();
  }

  Future<File> writeTo(String configPath) async {
    final file = File(configPath);
    await file.parent.create(recursive: true);
    final tmp = File('$configPath.tmp');
    await tmp.writeAsString(toToml(), flush: true);
    if (!Platform.isWindows) {
      final chmod = await Process.run('chmod', ['600', tmp.path]);
      if (chmod.exitCode != 0) {
        throw FileSystemException('无法把配置文件权限设为 0600：${chmod.stderr}', tmp.path);
      }
    }
    if (Platform.isWindows && await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
    return file;
  }

  static String _escape(String value) {
    if (value.contains('\n') || value.contains('\r')) {
      throw ArgumentError('路径/排除规则不能包含换行：$value');
    }
    return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }
}

/// 默认控制平面位置（与 CLI 一致），供 onboarding 预填/复用检测。
String defaultVaultDir([String? home]) {
  final base =
      home ??
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  if (base == null || base.isEmpty) {
    throw StateError('无法确定用户主目录');
  }
  return p.join(base, '.eimmortal', 'eimmortal-vault');
}
