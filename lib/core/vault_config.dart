import 'dart:io';

import 'package:path/path.dart' as p;

/// GUI 维护的最小 `config.toml`。
///
/// 只写白名单字段，不接管用户已有的完整配置；字段语义见核心
/// `config.example.toml`。POSIX 上必须落成 0600，否则 CLI 以 E2 拒绝启动。
class VaultConfig {
  const VaultConfig({
    required this.vaultDir,
    required this.targetDir,
    this.stagingDir,
    this.ignoreXattr = true,
    this.sessionMaxMib = 1024,
    this.exclude = const <String>[],
  });

  final String vaultDir;
  final String targetDir;
  final String? stagingDir;

  /// macOS 默认 true：接受 xattr/ACL 无法还原，避免 com.apple.provenance 触发 E21。
  final bool ignoreXattr;

  /// 单次 backup 的明文上限（MiB）。
  final int sessionMaxMib;

  final List<String> exclude;

  String toToml() {
    final buffer = StringBuffer()
      ..writeln('[vault]')
      ..writeln('dir = "${_escape(vaultDir)}"')
      ..writeln()
      ..writeln('[storage]')
      ..writeln('target_dir = "${_escape(targetDir)}"');
    if (stagingDir != null && stagingDir!.isNotEmpty) {
      buffer.writeln('staging_dir = "${_escape(stagingDir!)}"');
    }
    buffer
      ..writeln('session_max_mib = $sessionMaxMib')
      ..writeln()
      ..writeln('[scan]')
      ..writeln('ignore_xattr = $ignoreXattr');
    if (exclude.isNotEmpty) {
      buffer.write('exclude = [');
      buffer.write(exclude.map((rule) => '"${_escape(rule)}"').join(', '));
      buffer.writeln(']');
    }
    return buffer.toString();
  }

  Future<File> writeTo(String configPath) async {
    final file = File(configPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(toToml(), flush: true);
    if (!Platform.isWindows) {
      final chmod = await Process.run('chmod', ['600', file.path]);
      if (chmod.exitCode != 0) {
        throw FileSystemException(
          '无法把配置文件权限设为 0600：${chmod.stderr}',
          file.path,
        );
      }
    }
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
  final base = home ?? Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (base == null || base.isEmpty) {
    throw StateError('无法确定用户主目录');
  }
  return p.join(base, '.eimmortal', 'eimmortal-vault');
}
