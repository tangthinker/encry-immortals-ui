import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class TargetLockInfo {
  const TargetLockInfo({
    required this.path,
    required this.exists,
    this.hostId,
    this.pid,
    this.bootId,
    this.startedAt,
    this.toolVersion,
    this.raw,
    this.legacyPath,
    this.legacyExists = false,
  });

  final String path;
  final bool exists;
  final String? hostId;
  final int? pid;
  final String? bootId;
  final DateTime? startedAt;
  final String? toolVersion;
  final String? raw;
  final String? legacyPath;
  final bool legacyExists;

  bool get locked => exists || legacyExists;

  static Future<TargetLockInfo> inspect(String targetDir) async {
    final path = p.join(targetDir, '.eimmortal.lock');
    final legacy = p.join(targetDir, '.apex.lock');
    final file = File(path);
    final legacyFile = File(legacy);
    final legacyExists = await legacyFile.exists();
    if (!await file.exists()) {
      return TargetLockInfo(
        path: path,
        exists: false,
        legacyPath: legacy,
        legacyExists: legacyExists,
      );
    }
    final raw = await file.readAsString();
    Map<String, Object?>? payload;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        payload = decoded.map((key, value) => MapEntry('$key', value));
      }
    } on FormatException {
      payload = null;
    }
    final startedUnix = payload?['started_unix'];
    return TargetLockInfo(
      path: path,
      exists: true,
      hostId: payload?['host_id']?.toString(),
      pid: payload?['pid'] is int ? payload!['pid'] as int : null,
      bootId: payload?['boot_id']?.toString(),
      startedAt: startedUnix is int
          ? DateTime.fromMillisecondsSinceEpoch(startedUnix * 1000)
          : null,
      toolVersion: payload?['tool_version']?.toString(),
      raw: raw,
      legacyPath: legacy,
      legacyExists: legacyExists,
    );
  }

  /// 只在用户明确确认“没有其他备份进程”后调用。
  static Future<void> delete(String targetDir) async {
    final current = File(p.join(targetDir, '.eimmortal.lock'));
    if (await current.exists()) await current.delete();
    final legacy = File(p.join(targetDir, '.apex.lock'));
    if (await legacy.exists()) await legacy.delete();
  }
}

/// 控制面锁：Unix 是 flock（文件存在不代表被占用），Windows 是标记文件。
/// 因此这里只提供“探测写锁”的路径信息，真正是否被占用由运行一条
/// 无密码命令（status）来判断。
class ControlLockInfo {
  const ControlLockInfo({
    required this.path,
    required this.exists,
    required this.removableMarker,
  });

  final String path;
  final bool exists;

  /// 只有 Windows 的 O_EXCL 标记文件可以安全删除；Unix 删除文件不会释放 flock。
  final bool removableMarker;

  static Future<ControlLockInfo> inspect(String vaultDir) async {
    final path = p.join(vaultDir, 'lock');
    final exists = await File(path).exists();
    return ControlLockInfo(
      path: path,
      exists: exists,
      removableMarker: Platform.isWindows,
    );
  }

  static Future<void> deleteMarker(String vaultDir) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Unix 控制锁是 flock，删除锁文件不会释放占用。');
    }
    final file = File(p.join(vaultDir, 'lock'));
    if (await file.exists()) await file.delete();
  }
}
