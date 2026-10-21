import 'dart:io';

import 'private_file.dart';

/// 应用级单实例锁。文件锁随进程退出自动释放；第二个实例会拿到 null。
class InstanceLock {
  InstanceLock._(this._file, this.path);

  final RandomAccessFile _file;
  final String path;

  static Future<InstanceLock?> acquire(String path) async {
    final file = await File(path).open(mode: FileMode.append);
    try {
      await file.lock(FileLock.exclusive);
    } on FileSystemException {
      await file.close();
      return null;
    }
    await makePrivateFile(path);
    return InstanceLock._(file, path);
  }

  Future<void> release() async {
    try {
      await _file.unlock();
    } finally {
      await _file.close();
    }
  }
}
