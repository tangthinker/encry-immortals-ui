import 'dart:convert';
import 'dart:io';

import 'package:encry_immortals_ui/core/lock_inspector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('eimmortal_lock_');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('没有锁文件时不标记 locked', () async {
    final info = await TargetLockInfo.inspect(temp.path);
    expect(info.exists, isFalse);
    expect(info.locked, isFalse);
  });

  test('读取目标写锁的 host/pid/时间', () async {
    await File(p.join(temp.path, '.eimmortal.lock')).writeAsString(
      jsonEncode({
        'host_id': 'mac',
        'pid': 123,
        'boot_id': 'boot',
        'started_unix': 1700000000,
        'tool_version': '0.1.0-dev',
      }),
    );
    final info = await TargetLockInfo.inspect(temp.path);
    expect(info.exists, isTrue);
    expect(info.locked, isTrue);
    expect(info.hostId, 'mac');
    expect(info.pid, 123);
    expect(info.toolVersion, '0.1.0-dev');
    expect(info.startedAt?.toUtc().year, 2023);
  });

  test('legacy .apex.lock 也视为写入中', () async {
    await File(p.join(temp.path, '.apex.lock')).writeAsString('old');
    final info = await TargetLockInfo.inspect(temp.path);
    expect(info.exists, isFalse);
    expect(info.legacyExists, isTrue);
    expect(info.locked, isTrue);
  });

  test('确认后删除目标锁', () async {
    final lock = File(p.join(temp.path, '.eimmortal.lock'));
    await lock.writeAsString('{}');
    await TargetLockInfo.delete(temp.path);
    expect(lock.existsSync(), isFalse);
  });

  test('非 Windows 上控制锁是 flock，不能靠删文件修复', () async {
    final info = await ControlLockInfo.inspect(temp.path);
    expect(info.path, p.join(temp.path, 'lock'));
    if (!Platform.isWindows) {
      expect(info.removableMarker, isFalse);
      await expectLater(
        () => ControlLockInfo.deleteMarker(temp.path),
        throwsUnsupportedError,
      );
    }
  });
}
