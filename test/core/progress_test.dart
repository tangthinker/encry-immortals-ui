import 'package:encry_immortals_ui/core/progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析带速度和当前路径的备份进度', () {
    final progress = parseCoreProgress(
      '备份进度 3/10 文件 · 1.0 MiB/2.0 MiB（50%）· 12.3 MiB/s · 当前 docs/a.txt',
    );
    expect(progress, isNotNull);
    expect(progress!.phase, 'backup');
    expect(progress.doneFiles, 3);
    expect(progress.totalFiles, 10);
    expect(progress.doneText, '1.0 MiB');
    expect(progress.totalText, '2.0 MiB');
    expect(progress.percent, 50);
    expect(progress.speedMibPerSecond, 12.3);
    expect(progress.current, 'docs/a.txt');
  });

  test('解析不带速度的还原进度', () {
    final progress = parseCoreProgress(
      '还原进度 1/2 文件 · 512 KiB/1.0 MiB（50%）· 当前 photo.jpg',
    );
    expect(progress?.phase, 'restore');
    expect(progress?.current, 'photo.jpg');
    expect(progress?.speedMibPerSecond, isNull);
  });

  test('无关日志返回 null', () {
    expect(parseCoreProgress('正在写入 pack…'), isNull);
    expect(parseCoreProgress('备份进度 1/3'), isNull);
  });
}
