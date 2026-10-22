import 'package:encry_immortals_ui/core/backup_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('每天在指定时间，错过则顺延到明天', () {
    const schedule = BackupSchedule(
      mode: BackupScheduleMode.daily,
      hour: 2,
      minute: 30,
    );
    expect(
      schedule.nextAfter(DateTime(2026, 10, 22, 1)),
      DateTime(2026, 10, 22, 2, 30),
    );
    expect(
      schedule.nextAfter(DateTime(2026, 10, 22, 3)),
      DateTime(2026, 10, 23, 2, 30),
    );
  });

  test('每周按星期与时间计算', () {
    const schedule = BackupSchedule(
      mode: BackupScheduleMode.weekly,
      weekday: DateTime.monday,
      hour: 2,
    );
    // 2026-10-22 是周四。
    expect(
      schedule.nextAfter(DateTime(2026, 10, 22, 3)),
      DateTime(2026, 10, 26, 2),
    );
    expect(
      schedule.nextAfter(DateTime(2026, 10, 19, 1)),
      DateTime(2026, 10, 19, 2),
    );
    expect(
      schedule.nextAfter(DateTime(2026, 10, 19, 3)),
      DateTime(2026, 10, 26, 2),
    );
  });

  test('每月 31 日在短月份使用最后一天', () {
    const schedule = BackupSchedule(
      mode: BackupScheduleMode.monthly,
      dayOfMonth: 31,
      hour: 2,
    );
    expect(
      schedule.nextAfter(DateTime(2026, 1, 30, 23)),
      DateTime(2026, 1, 31, 2),
    );
    expect(schedule.nextAfter(DateTime(2026, 2, 1)), DateTime(2026, 2, 28, 2));
    expect(
      schedule.nextAfter(DateTime(2026, 2, 28, 3)),
      DateTime(2026, 3, 31, 2),
    );
  });

  test('固定间隔从当前时间之后计算', () {
    const schedule = BackupSchedule(
      mode: BackupScheduleMode.interval,
      intervalMinutes: 90,
    );
    expect(
      schedule.nextAfter(DateTime(2026, 10, 22, 10)),
      DateTime(2026, 10, 22, 11, 30),
    );
    expect(schedule.description, '每 90 分钟');
  });

  test('关闭状态没有下次执行时间', () {
    const schedule = BackupSchedule();
    expect(schedule.isEnabled, isFalse);
    expect(schedule.nextAfter(DateTime(2026, 10, 22)), isNull);
    expect(schedule.validate(), isNull);
  });

  test('边界校验', () {
    expect(const BackupSchedule(hour: 24).validate(), isNotNull);
    expect(const BackupSchedule(minute: 60).validate(), isNotNull);
    expect(const BackupSchedule(weekday: 0).validate(), isNotNull);
    expect(const BackupSchedule(dayOfMonth: 32).validate(), isNotNull);
    expect(const BackupSchedule(intervalMinutes: 4).validate(), isNotNull);
    expect(
      const BackupSchedule(intervalMinutes: 30 * 24 * 60 + 1).validate(),
      isNotNull,
    );
  });

  test('JSON 往返保留计划、下次/上次与错误', () {
    final schedule = BackupSchedule(
      mode: BackupScheduleMode.weekly,
      weekday: DateTime.friday,
      hour: 23,
      minute: 15,
      nextRunAt: DateTime(2026, 10, 30, 23, 15),
      lastRunAt: DateTime(2026, 10, 23, 23, 15),
      lastError: 'exit 20 · locked',
    );
    final decoded = BackupSchedule.fromJson(schedule.toJson());
    expect(decoded.mode, BackupScheduleMode.weekly);
    expect(decoded.weekday, DateTime.friday);
    expect(decoded.hour, 23);
    expect(decoded.minute, 15);
    expect(decoded.nextRunAt?.toUtc(), schedule.nextRunAt?.toUtc());
    expect(decoded.lastRunAt?.toUtc(), schedule.lastRunAt?.toUtc());
    expect(decoded.lastError, schedule.lastError);
    expect(decoded.description, '每周五 23:15');
  });

  test('非法 JSON 值回退到安全默认', () {
    final decoded = BackupSchedule.fromJson({
      'mode': 'unknown',
      'hour': -1,
      'minute': 99,
      'weekday': 0,
      'day_of_month': 99,
      'interval_minutes': 1,
    });
    expect(decoded.mode, BackupScheduleMode.off);
    expect(decoded.hour, 0);
    expect(decoded.minute, 59);
    expect(decoded.weekday, 1);
    expect(decoded.dayOfMonth, 31);
    expect(decoded.intervalMinutes, 5);
  });
}
