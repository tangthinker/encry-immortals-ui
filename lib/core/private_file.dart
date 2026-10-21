import 'dart:io';

/// Dart 没有 chmod API；POSIX 上用 `chmod` 保证配置与控制面只对当前用户可见。
/// Windows 依赖用户目录 ACL，不做 mode 检查。
Future<void> makePrivateFile(String path) async {
  if (Platform.isWindows) return;
  final result = await Process.run('chmod', ['600', path]);
  if (result.exitCode != 0) {
    throw FileSystemException(
      '无法把文件权限设为 0600：${result.stderr}',
      path,
    );
  }
}

Future<void> makePrivateDirectory(String path) async {
  if (Platform.isWindows) return;
  final result = await Process.run('chmod', ['700', path]);
  if (result.exitCode != 0) {
    throw FileSystemException(
      '无法把目录权限设为 0700：${result.stderr}',
      path,
    );
  }
}
