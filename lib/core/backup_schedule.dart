/// 应用级定时备份计划。密码从不落盘：只有应用运行且已解锁时才会执行。
enum BackupScheduleMode {
  off,
  daily,
  weekly,
  monthly,
  interval;

  String get label => switch (this) {
    BackupScheduleMode.off => '关闭',
    BackupScheduleMode.daily => '每天',
    BackupScheduleMode.weekly => '每周',
    BackupScheduleMode.monthly => '每月',
    BackupScheduleMode.interval => '固定间隔',
  };

  static BackupScheduleMode parse(Object? value) {
    return switch (value) {
      'daily' => BackupScheduleMode.daily,
      'weekly' => BackupScheduleMode.weekly,
      'monthly' => BackupScheduleMode.monthly,
      'interval' => BackupScheduleMode.interval,
      _ => BackupScheduleMode.off,
    };
  }
}

class BackupSchedule {
  const BackupSchedule({
    this.mode = BackupScheduleMode.off,
    this.hour = 2,
    this.minute = 0,
    this.weekday = DateTime.monday,
    this.dayOfMonth = 1,
    this.intervalMinutes = 360,
    this.nextRunAt,
    this.lastRunAt,
    this.lastError,
  });

  final BackupScheduleMode mode;
  final int hour;
  final int minute;
  final int weekday;
  final int dayOfMonth;
  final int intervalMinutes;
  final DateTime? nextRunAt;
  final DateTime? lastRunAt;
  final String? lastError;

  bool get isEnabled => mode != BackupScheduleMode.off;

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String get weekdayLabel =>
      const ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday.clamp(1, 7)];

  String get intervalLabel {
    if (intervalMinutes % 1440 == 0) {
      return '每 ${intervalMinutes ~/ 1440} 天';
    }
    if (intervalMinutes % 60 == 0) {
      return '每 ${intervalMinutes ~/ 60} 小时';
    }
    return '每 $intervalMinutes 分钟';
  }

  String get description => switch (mode) {
    BackupScheduleMode.off => '未启用',
    BackupScheduleMode.daily => '每天 $timeLabel',
    BackupScheduleMode.weekly => '每$weekdayLabel $timeLabel',
    BackupScheduleMode.monthly => '每月 $dayOfMonth 日 $timeLabel',
    BackupScheduleMode.interval => intervalLabel,
  };

  String? validate() {
    if (hour < 0 || hour > 23) return '小时必须在 0..23 之间。';
    if (minute < 0 || minute > 59) return '分钟必须在 0..59 之间。';
    if (weekday < 1 || weekday > 7) return '星期必须在周一到周日之间。';
    if (dayOfMonth < 1 || dayOfMonth > 31) return '每月日期必须在 1..31 之间。';
    if (intervalMinutes < 5 || intervalMinutes > 30 * 24 * 60) {
      return '固定间隔必须在 5 分钟..30 天之间。';
    }
    return null;
  }

  /// 从 [from] 之后计算下一次执行时间；关闭时返回 null。
  DateTime? nextAfter(DateTime from) {
    switch (mode) {
      case BackupScheduleMode.off:
        return null;
      case BackupScheduleMode.interval:
        return from.add(Duration(minutes: intervalMinutes));
      case BackupScheduleMode.daily:
        var candidate = DateTime(from.year, from.month, from.day, hour, minute);
        if (!candidate.isAfter(from)) {
          candidate = DateTime(
            from.year,
            from.month,
            from.day + 1,
            hour,
            minute,
          );
        }
        return candidate;
      case BackupScheduleMode.weekly:
        final daysAhead = (weekday - from.weekday) % 7;
        var candidate = DateTime(
          from.year,
          from.month,
          from.day + daysAhead,
          hour,
          minute,
        );
        if (!candidate.isAfter(from)) {
          candidate = DateTime(
            from.year,
            from.month,
            from.day + 7,
            hour,
            minute,
          );
        }
        return candidate;
      case BackupScheduleMode.monthly:
        DateTime candidateFor(int year, int month) {
          final lastDay = DateTime(year, month + 1, 0).day;
          final day = dayOfMonth.clamp(1, lastDay);
          return DateTime(year, month, day, hour, minute);
        }

        var candidate = candidateFor(from.year, from.month);
        if (!candidate.isAfter(from)) {
          candidate = candidateFor(from.year, from.month + 1);
        }
        return candidate;
    }
  }

  BackupSchedule copyWith({
    BackupScheduleMode? mode,
    int? hour,
    int? minute,
    int? weekday,
    int? dayOfMonth,
    int? intervalMinutes,
    DateTime? nextRunAt,
    DateTime? lastRunAt,
    String? lastError,
    bool clearNextRunAt = false,
    bool clearLastError = false,
  }) {
    return BackupSchedule(
      mode: mode ?? this.mode,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      weekday: weekday ?? this.weekday,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      nextRunAt: clearNextRunAt ? null : nextRunAt ?? this.nextRunAt,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'hour': hour,
    'minute': minute,
    'weekday': weekday,
    'day_of_month': dayOfMonth,
    'interval_minutes': intervalMinutes,
    'next_run_at': nextRunAt?.toUtc().toIso8601String(),
    'last_run_at': lastRunAt?.toUtc().toIso8601String(),
    'last_error': lastError,
  };

  factory BackupSchedule.fromJson(Map<String, Object?> json) {
    int integer(String key, int fallback) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? fallback;
    }

    final mode = BackupScheduleMode.parse(json['mode']);
    DateTime? date(String key) {
      final raw = json[key];
      if (raw is! String) return null;
      return DateTime.tryParse(raw)?.toLocal();
    }

    final schedule = BackupSchedule(
      mode: mode,
      hour: integer('hour', 2).clamp(0, 23),
      minute: integer('minute', 0).clamp(0, 59),
      weekday: integer('weekday', DateTime.monday).clamp(1, 7),
      dayOfMonth: integer('day_of_month', 1).clamp(1, 31),
      intervalMinutes: integer('interval_minutes', 360).clamp(5, 30 * 24 * 60),
      nextRunAt: date('next_run_at'),
      lastRunAt: date('last_run_at'),
      lastError:
          json['last_error'] is String &&
              (json['last_error'] as String).isNotEmpty
          ? json['last_error'] as String
          : null,
    );
    return schedule;
  }
}

String formatScheduleDateTime(DateTime? value) {
  if (value == null) return '—';
  String two(int number) => number.toString().padLeft(2, '0');
  final local = value.toLocal();
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
