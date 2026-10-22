import 'package:flutter/material.dart';

import '../../core/backup_schedule.dart';
import '../app_controller.dart';
import '../theme.dart';
import 'section_card.dart';

class BackupScheduleCard extends StatefulWidget {
  const BackupScheduleCard({
    required this.controller,
    this.enabled = true,
    super.key,
  });

  final AppController controller;
  final bool enabled;

  @override
  State<BackupScheduleCard> createState() => _BackupScheduleCardState();
}

class _BackupScheduleCardState extends State<BackupScheduleCard> {
  late BackupScheduleMode _mode;
  late int _hour;
  late int _minute;
  late int _weekday;
  late int _dayOfMonth;
  late TextEditingController _interval;
  late String _intervalUnit;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _interval = TextEditingController();
    _interval.addListener(_clearErrorOnEdit);
    _apply(widget.controller.backupSchedule);
  }

  void _apply(BackupSchedule schedule) {
    _mode = schedule.mode;
    _hour = schedule.hour;
    _minute = schedule.minute;
    _weekday = schedule.weekday;
    _dayOfMonth = schedule.dayOfMonth;
    if (schedule.intervalMinutes % 1440 == 0) {
      _intervalUnit = 'days';
      _interval.text = '${schedule.intervalMinutes ~/ 1440}';
    } else if (schedule.intervalMinutes % 60 == 0) {
      _intervalUnit = 'hours';
      _interval.text = '${schedule.intervalMinutes ~/ 60}';
    } else {
      _intervalUnit = 'minutes';
      _interval.text = '${schedule.intervalMinutes}';
    }
  }

  void _clearErrorOnEdit() {
    if (_error != null && mounted) setState(() => _error = null);
  }

  @override
  void dispose() {
    _interval
      ..removeListener(_clearErrorOnEdit)
      ..dispose();
    super.dispose();
  }

  String get _timeLabel =>
      '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}';

  int get _intervalMinutes {
    final amount = int.tryParse(_interval.text.trim()) ?? 0;
    return switch (_intervalUnit) {
      'days' => amount * 1440,
      'hours' => amount * 60,
      _ => amount,
    };
  }

  BackupSchedule _read() {
    final current = widget.controller.backupSchedule;
    return BackupSchedule(
      mode: _mode,
      hour: _hour,
      minute: _minute,
      weekday: _weekday,
      dayOfMonth: _dayOfMonth,
      intervalMinutes: _mode == BackupScheduleMode.interval
          ? _intervalMinutes
          : current.intervalMinutes,
      lastRunAt: current.lastRunAt,
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
      helpText: '选择定时备份时间',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _hour = picked.hour;
      _minute = picked.minute;
      _error = null;
    });
  }

  Future<void> _save() async {
    final schedule = _read();
    final error = schedule.validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.updateBackupSchedule(schedule);
      if (!mounted) return;
      setState(() => _apply(widget.controller.backupSchedule));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            schedule.isEnabled
                ? '定时备份已保存：${widget.controller.backupSchedule.description}'
                : '定时备份已关闭。',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.controller.backupSchedule;
    final canEdit =
        widget.enabled && !_saving && !widget.controller.scheduledBackupRunning;
    final busy = widget.controller.scheduledBackupRunning;
    final next = current.nextRunAt;
    final overdue = next != null && !next.isAfter(DateTime.now());

    return SectionCard(
      title: '定时备份',
      subtitle: '每天 / 每周 / 每月或固定间隔；仅在应用运行且已解锁时执行',
      trailing: FilledButton(
        onPressed: canEdit ? _save : null,
        child: Text(_saving ? '保存中…' : '保存计划'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<BackupScheduleMode>(
            key: ValueKey('schedule-mode-$_mode'),
            initialValue: _mode,
            decoration: const InputDecoration(labelText: '频率'),
            items: [
              for (final mode in BackupScheduleMode.values)
                DropdownMenuItem(value: mode, child: Text(mode.label)),
            ],
            onChanged: canEdit
                ? (value) {
                    setState(() {
                      _mode = value ?? BackupScheduleMode.off;
                      _error = null;
                    });
                  }
                : null,
          ),
          if (_mode != BackupScheduleMode.off) ...[
            const SizedBox(height: 14),
            if (_mode == BackupScheduleMode.daily ||
                _mode == BackupScheduleMode.weekly ||
                _mode == BackupScheduleMode.monthly) ...[
              Row(
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: '执行时间',
                        helperText: '本地时区；24 小时制',
                      ),
                      child: Text(_timeLabel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: canEdit ? _pickTime : null,
                    child: const Text('选择时间'),
                  ),
                ],
              ),
            ],
            if (_mode == BackupScheduleMode.weekly) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey('weekday-$_weekday'),
                initialValue: _weekday,
                decoration: const InputDecoration(labelText: '星期'),
                items: [
                  for (var day = 1; day <= 7; day++)
                    DropdownMenuItem(
                      value: day,
                      child: Text(
                        const [
                          '',
                          '周一',
                          '周二',
                          '周三',
                          '周四',
                          '周五',
                          '周六',
                          '周日',
                        ][day],
                      ),
                    ),
                ],
                onChanged: canEdit
                    ? (value) => setState(() {
                        _weekday = value ?? 1;
                        _error = null;
                      })
                    : null,
              ),
            ],
            if (_mode == BackupScheduleMode.monthly) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey('monthday-$_dayOfMonth'),
                initialValue: _dayOfMonth,
                decoration: const InputDecoration(
                  labelText: '每月日期',
                  helperText: '没有该日期的月份使用最后一天',
                ),
                items: [
                  for (var day = 1; day <= 31; day++)
                    DropdownMenuItem(value: day, child: Text('$day 日')),
                ],
                onChanged: canEdit
                    ? (value) => setState(() {
                        _dayOfMonth = value ?? 1;
                        _error = null;
                      })
                    : null,
              ),
            ],
            if (_mode == BackupScheduleMode.interval) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _interval,
                      enabled: canEdit,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '间隔',
                        helperText: '最短 5 分钟，最长 30 天',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 130,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('interval-unit-$_intervalUnit'),
                      initialValue: _intervalUnit,
                      decoration: const InputDecoration(labelText: '单位'),
                      items: const [
                        DropdownMenuItem(value: 'minutes', child: Text('分钟')),
                        DropdownMenuItem(value: 'hours', child: Text('小时')),
                        DropdownMenuItem(value: 'days', child: Text('天')),
                      ],
                      onChanged: canEdit
                          ? (value) => setState(() {
                              _intervalUnit = value ?? 'minutes';
                              _error = null;
                            })
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            NoticeBanner(
              title: '计划未保存',
              message: _error!,
              color: AppColors.danger,
              icon: Icons.error_outline_rounded,
            ),
          ],
          const SizedBox(height: 16),
          const Divider(),
          InfoRow(
            label: '当前计划',
            value: current.description,
            valueColor: current.isEnabled ? AppColors.text : AppColors.faint,
          ),
          const Divider(),
          InfoRow(
            label: '下次执行',
            value: widget.controller.scheduledBackupRunning
                ? '正在运行…'
                : busy
                ? '等待当前命令结束'
                : next == null
                ? '—'
                : overdue
                ? '${formatScheduleDateTime(next)}（已到点，等待解锁）'
                : formatScheduleDateTime(next),
            valueColor: overdue && current.isEnabled
                ? AppColors.amber
                : AppColors.text,
          ),
          const Divider(),
          InfoRow(
            label: '上次执行',
            value: current.lastRunAt == null
                ? '—'
                : formatScheduleDateTime(current.lastRunAt),
          ),
          if (current.lastError != null) ...[
            const Divider(),
            InfoRow(
              label: '上次结果',
              value: current.lastError!,
              valueColor: AppColors.danger,
            ),
          ],
          const SizedBox(height: 12),
          NoticeBanner(
            title: '应用必须保持运行并已解锁',
            message:
                '主密码不会写入磁盘，因此锁定时无法自动解锁。到点若处于锁定状态，'
                '会在解锁后补跑一次；应用完全退出时不会执行。',
            color: AppColors.amber,
            icon: Icons.warning_amber_rounded,
          ),
        ],
      ),
    );
  }
}
