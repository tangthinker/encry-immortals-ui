import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../backup_continuation.dart';
import '../../core/core_exit_code.dart';
import '../../core/core_models.dart';
import '../../core/core_result.dart';
import '../../core/lock_inspector.dart';
import '../../core/progress.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/log_panel.dart';
import '../widgets/page_header.dart';
import '../widgets/section_card.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({required this.controller, super.key});

  final AppController controller;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final TextEditingController _message = TextEditingController();
  bool _running = false;
  bool _dryRun = false;
  BackupSummary? _summary;
  String? _error;
  CoreExitCode? _exitCode;
  CoreProgress? _progress;
  List<String> _logs = [];
  TargetLockInfo? _lockInfo;
  bool _checkingLock = false;
  String? _lockDetail;
  bool _continuous = false;
  bool _stopContinuous = false;
  bool _continuousStopped = false;
  bool _continuousNoProgress = false;
  bool _continuousLimitReached = false;
  int _continuousCommits = 0;
  int _iteration = 0;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _start({required bool dryRun, bool breakLock = false}) {
    return _runBackup(dryRun: dryRun, breakLock: breakLock);
  }

  Future<void> _startContinuous() {
    return _runBackup(dryRun: false, continuous: true);
  }

  void _requestStopContinuous() {
    if (!_continuous || _stopContinuous) return;
    setState(() => _stopContinuous = true);
  }

  Future<void> _runBackup({
    required bool dryRun,
    bool breakLock = false,
    bool continuous = false,
  }) async {
    if (_running) return;
    final session = widget.controller.session;
    final profile = widget.controller.profile;
    if (session == null || profile == null) return;
    if (!profile.sourceExists) {
      setState(() {
        _error = '源目录不存在：${profile.sourceRoot}';
        _exitCode = null;
      });
      return;
    }
    setState(() {
      _running = true;
      _dryRun = dryRun;
      _summary = null;
      _error = null;
      _exitCode = null;
      _progress = null;
      _logs = [];
      _lockInfo = null;
      _lockDetail = null;
      _continuous = continuous;
      _stopContinuous = false;
      _continuousStopped = false;
      _continuousNoProgress = false;
      _continuousLimitReached = false;
      _continuousCommits = 0;
      _iteration = 0;
    });

    int? previousSeq;
    var iteration = 0;
    while (true) {
      iteration++;
      if (!mounted) return;
      setState(() {
        _iteration = iteration;
        _progress = null;
        _summary = null;
        if (iteration > 1) {
          _logs = [..._logs, '── 第 $iteration 次提交 ──'];
          if (_logs.length > 500) {
            _logs = _logs.sublist(_logs.length - 500);
          }
        }
      });

      void onStderr(String line) {
        if (!mounted) return;
        setState(() {
          _logs = [..._logs, line];
          if (_logs.length > 500) {
            _logs = _logs.sublist(_logs.length - 500);
          }
          final parsed = parseCoreProgress(line);
          if (parsed != null) _progress = parsed;
        });
      }

      CoreResult result;
      try {
        result = await session.backup(
          dryRun: dryRun,
          breakLock: breakLock,
          message: _message.text,
          onStderr: onStderr,
        );
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _running = false;
          _continuous = false;
          _error = _continuousCommits > 0
              ? '持续备份完成 $_continuousCommits 次提交后异常：$error'
              : '备份命令异常：$error';
          _exitCode = null;
        });
        return;
      }
      if (!mounted) return;

      await widget.controller.refreshTargetLock();
      if (!mounted) return;

      if (!result.isSuccess) {
        setState(() {
          _running = false;
          _continuous = false;
          _error = _continuousCommits > 0
              ? '持续备份完成 $_continuousCommits 次提交后失败：${_messageFor(result)}'
              : _messageFor(result);
          _exitCode = result.exit;
        });
        if (result.exit == CoreExitCode.locked ||
            result.exit == CoreExitCode.interrupted ||
            result.cancelled) {
          await _checkLocks();
        }
        return;
      }

      final summary = result.jsonMap == null
          ? null
          : BackupSummary.fromJson(result.jsonMap!);
      if (summary == null) {
        setState(() {
          _running = false;
          _continuous = false;
          _error = '备份返回成功，但 JSON 结构无法解析（协议漂移）。';
          _exitCode = null;
        });
        return;
      }

      widget.controller.markDataChanged();
      final progressed = backupHasProgress(summary, previousSeq: previousSeq);
      previousSeq = summary.seq;
      if (continuous) {
        setState(() => _continuousCommits++);
      }

      final hitIterationLimit =
          continuous && iteration >= maxContinuousBackupCommits;
      final shouldStop =
          !continuous ||
          !summary.truncated ||
          _stopContinuous ||
          !progressed ||
          hitIterationLimit;

      if (shouldStop) {
        setState(() {
          _running = false;
          _continuous = false;
          _summary = summary;
          _progress = null;
          _continuousStopped =
              continuous && summary.truncated && _stopContinuous;
          _continuousNoProgress =
              continuous && summary.truncated && !progressed;
          _continuousLimitReached =
              continuous && summary.truncated && hitIterationLimit;
        });
        return;
      }
    }
  }

  String _messageFor(CoreResult result) {
    final exit = result.exit;
    final summary = result.errorSummary;
    final extra = summary == exit.label ? '' : '\n$summary';
    return '${exit.label}（exit ${result.exitCode}）· ${exit.guidance}$extra';
  }

  Future<void> _checkLocks() async {
    final session = widget.controller.session;
    final profile = widget.controller.profile;
    if (session == null || profile == null) return;
    setState(() {
      _checkingLock = true;
      _lockDetail = null;
    });
    try {
      final targetLock = await TargetLockInfo.inspect(profile.targetDir);
      final probe = await session.probeControlLock();
      if (!mounted) return;
      setState(() {
        _lockInfo = targetLock;
        _lockDetail = probe.exitCode == 20
            ? '控制锁被其他进程占用：${profile.vaultDir}/lock'
            : '控制锁可获取；TargetDir 写锁${targetLock.locked ? '存在' : '不存在'}。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _lockDetail = '$error');
    } finally {
      if (mounted) setState(() => _checkingLock = false);
    }
  }

  Future<void> _retryWithBreakLock() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('使用 --break-lock 重试？'),
        content: const Text(
          '请先确认没有其他 eimmortal 或备份进程在写入这个 TargetDir。'
          '该选项会删除 TargetDir 的 .eimmortal.lock 并继续备份。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认并重试'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _start(dryRun: false, breakLock: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final profile = controller.profile;
    final busy = _running || controller.queue.isBusy;
    final sourceMissing = profile != null && !profile.sourceExists;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: '备份',
                subtitle: '增量扫描 → 压缩加密 → 写入 TargetDir；云端同步由网盘客户端负责',
                trailing: StatusPill(
                  label: _running ? '运行中' : '空闲',
                  color: _running ? AppColors.blue : AppColors.faint,
                  dense: true,
                ),
              ),
              const SizedBox(height: 22),
              SectionCard(
                title: '备份参数',
                subtitle: '源根目录已固定；只允许备份这个目录',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InfoRow(
                      label: '源目录',
                      value: profile?.sourceRoot ?? '—',
                      mono: true,
                      selectable: true,
                      valueColor: sourceMissing ? AppColors.danger : null,
                      trailing: IconButton(
                        onPressed: profile == null
                            ? null
                            : () => controller.platform.revealPath(
                                profile.sourceRoot,
                              ),
                        icon: const Icon(Icons.folder_open_rounded, size: 16),
                        tooltip: '在文件管理器中打开',
                      ),
                    ),
                    const Divider(),
                    InfoRow(
                      label: 'TargetDir',
                      value: profile?.targetDir ?? '—',
                      mono: true,
                      selectable: true,
                      trailing: IconButton(
                        onPressed: profile == null
                            ? null
                            : () => controller.platform.revealPath(
                                profile.targetDir,
                              ),
                        icon: const Icon(Icons.folder_open_rounded, size: 16),
                        tooltip: '在文件管理器中打开',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _message,
                      enabled: !busy,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        labelText: '提交信息（可选）',
                        hintText: '例如：日常增量',
                        counterText: '',
                      ),
                    ),
                    if (sourceMissing) ...[
                      const SizedBox(height: 12),
                      NoticeBanner(
                        message: '源目录不可访问。请确认磁盘/网络位置已挂载，或重新创建 profile。',
                        color: AppColors.danger,
                        icon: Icons.folder_off_outlined,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: busy || sourceMissing
                              ? null
                              : () => _start(dryRun: true),
                          icon: const Icon(Icons.preview_outlined, size: 16),
                          label: const Text('预演'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: busy || sourceMissing
                              ? null
                              : () => _start(dryRun: false),
                          icon: busy
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.onAccent,
                                  ),
                                )
                              : const Icon(
                                  Icons.cloud_upload_outlined,
                                  size: 17,
                                ),
                          label: Text(busy ? '运行中…' : '开始备份'),
                        ),
                        const Spacer(),
                        Text(
                          'session_max_mib = ${profile?.sessionMaxMib ?? '—'}',
                          style: TextStyle(
                            fontFamily: 'Menlo',
                            fontSize: 10.5,
                            color: AppColors.faint,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_running) ...[
                const SizedBox(height: 18),
                _ProgressCard(
                  progress: _progress,
                  dryRun: _dryRun,
                  logs: _logs,
                  continuous: _continuous,
                  iteration: _iteration,
                  stopRequested: _stopContinuous,
                  onStop: _requestStopContinuous,
                ),
              ],
              if (_summary != null) ...[
                const SizedBox(height: 18),
                BackupResultCard(
                  summary: _summary!,
                  dryRun: _dryRun,
                  onContinue: () => _start(dryRun: false),
                  onContinuous: _startContinuous,
                  continuousCommits: _continuousCommits,
                  continuousStopped: _continuousStopped,
                  continuousNoProgress: _continuousNoProgress,
                  continuousLimitReached: _continuousLimitReached,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 18),
                SectionCard(
                  title: '操作失败',
                  accent: AppColors.danger,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      NoticeBanner(
                        title: _exitCode?.label,
                        message: _error!,
                        color: AppColors.danger,
                        icon: Icons.error_outline_rounded,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _checkingLock ? null : _checkLocks,
                            icon: const Icon(
                              Icons.lock_outline_rounded,
                              size: 16,
                            ),
                            label: Text(_checkingLock ? '检查中…' : '检查锁'),
                          ),
                          if (_lockInfo?.locked == true)
                            FilledButton.icon(
                              onPressed: busy ? null : _retryWithBreakLock,
                              icon: const Icon(
                                Icons.lock_open_rounded,
                                size: 16,
                              ),
                              label: const Text('使用 --break-lock 重试'),
                            ),
                        ],
                      ),
                      if (_lockDetail != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _lockDetail!,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.55,
                            color: AppColors.faint,
                          ),
                        ),
                      ],
                      if (_lockInfo?.locked == true) ...[
                        const SizedBox(height: 12),
                        _LockCard(info: _lockInfo!),
                      ],
                    ],
                  ),
                ),
              ],
              if (_logs.isNotEmpty && !_running) ...[
                const SizedBox(height: 18),
                SectionCard(
                  title: '运行日志',
                  subtitle: '只保留在内存中；包含本地路径，不会写入磁盘',
                  child: LogPanel(lines: _logs, height: 220),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.progress,
    required this.dryRun,
    required this.logs,
    required this.continuous,
    required this.iteration,
    required this.stopRequested,
    required this.onStop,
  });

  final CoreProgress? progress;
  final bool dryRun;
  final List<String> logs;
  final bool continuous;
  final int iteration;
  final bool stopRequested;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final percent = progress?.percent;
    return SectionCard(
      title: dryRun
          ? '正在预演'
          : continuous
          ? '持续备份中'
          : '正在备份',
      subtitle: continuous
          ? '第 $iteration 次提交 · 每次达到上限后自动继续'
          : '进度只用于展示；结果以最终 JSON 为准',
      trailing: Text(
        percent == null ? '准备中' : '$percent%',
        style: TextStyle(
          fontFamily: 'Menlo',
          fontSize: 12,
          color: AppColors.accent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: percent == null ? null : percent / 100,
            ),
          ),
          const SizedBox(height: 12),
          if (progress != null)
            Text(
              '${progress!.doneFiles}/${progress!.totalFiles} 文件 · '
              '${progress!.doneText}/${progress!.totalText}'
              '${progress!.speedMibPerSecond == null ? '' : ' · ${progress!.speedMibPerSecond!.toStringAsFixed(1)} MiB/s'}',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          if (progress?.current != null) ...[
            const SizedBox(height: 4),
            Text(
              progress!.current!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Menlo',
                fontSize: 10.5,
                color: AppColors.faint,
              ),
            ),
          ],
          if (continuous) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: stopRequested ? null : onStop,
                icon: const Icon(Icons.stop_circle_outlined, size: 16),
                label: Text(stopRequested ? '本次完成后停止…' : '停止持续备份'),
              ),
            ),
          ],
          if (logs.isNotEmpty) ...[
            const SizedBox(height: 12),
            LogPanel(lines: logs, height: 160),
          ],
        ],
      ),
    );
  }
}

class BackupResultCard extends StatelessWidget {
  const BackupResultCard({
    required this.summary,
    required this.dryRun,
    required this.onContinue,
    required this.onContinuous,
    required this.continuousCommits,
    required this.continuousStopped,
    required this.continuousNoProgress,
    required this.continuousLimitReached,
    super.key,
  });

  final BackupSummary summary;
  final bool dryRun;
  final VoidCallback onContinue;
  final VoidCallback onContinuous;
  final int continuousCommits;
  final bool continuousStopped;
  final bool continuousNoProgress;
  final bool continuousLimitReached;

  bool get _isContinuous => continuousCommits > 0;

  String get _title {
    if (dryRun) return '预演结果';
    if (_isContinuous) {
      if (continuousNoProgress || continuousLimitReached) {
        return '持续备份已停止';
      }
      if (continuousStopped || summary.truncated) {
        return '持续备份已暂停';
      }
      return '持续备份完成';
    }
    if (!summary.changed) return '没有变化';
    return '备份提交完成';
  }

  String get _subtitle {
    if (dryRun) return '预演不会写入 TargetDir';
    if (_isContinuous) {
      if (summary.truncated) {
        return '共完成 $continuousCommits 次提交；仍有剩余数据';
      }
      return '共完成 $continuousCommits 次提交；剩余数据已全部处理';
    }
    if (!summary.changed) return '源目录自上次提交以来没有变化';
    return '本地提交已写入；等待网盘客户端同步到云端';
  }

  String get _continuousMessage {
    if (continuousLimitReached) {
      return '已达到 $maxContinuousBackupCommits 次提交上限，为避免无限循环已停止。';
    }
    if (continuousNoProgress) {
      return '连续没有产生新的提交，可能单个文件超过 session_max_mib；'
          '可提高上限后再继续。';
    }
    if (summary.truncated) {
      return '已完成 $continuousCommits 次提交，仍有剩余数据；可稍后继续。';
    }
    return '共完成 $continuousCommits 次提交，所有可备份数据已处理完毕。';
  }

  @override
  Widget build(BuildContext context) {
    final warning = summary.truncated;
    return SectionCard(
      title: _title,
      subtitle: _subtitle,
      accent: warning
          ? AppColors.amber
          : summary.changed && !dryRun
          ? AppColors.success
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!dryRun && summary.changed)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  StatusPill(label: '已提交', color: AppColors.success),
                  const SizedBox(width: 10),
                  Text(
                    'seq ${summary.seq}',
                    style: TextStyle(
                      fontFamily: 'Menlo',
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          if (_isContinuous) ...[
            NoticeBanner(
              title: summary.truncated ? '仍有剩余数据' : '所有数据已处理',
              message: _continuousMessage,
              color: warning ? AppColors.amber : AppColors.success,
              icon: warning
                  ? Icons.pause_circle_outline_rounded
                  : Icons.check_circle_outline_rounded,
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              KeyValueChip(label: '新增', value: '${summary.added}'),
              KeyValueChip(label: '修改', value: '${summary.modified}'),
              KeyValueChip(label: '删除', value: '${summary.deleted}'),
              KeyValueChip(label: '目录', value: '${summary.dirs}'),
              KeyValueChip(label: '明文', value: formatBytes(summary.plainBytes)),
              KeyValueChip(
                label: 'pack',
                value: formatBytes(summary.packBytes),
              ),
              KeyValueChip(
                label: 'journal',
                value: formatBytes(summary.journalBytes),
              ),
            ],
          ),
          if (summary.skipped > 0) ...[
            const SizedBox(height: 12),
            NoticeBanner(
              message: '有 ${summary.skipped} 个文件在读取期间被修改而跳过，下次备份会重试。',
              color: AppColors.amber,
            ),
          ],
          if (summary.truncated) ...[
            const SizedBox(height: 12),
            NoticeBanner(
              title: '本次达到 session_max_mib 上限',
              message: '本次只提交了部分改动，剩余文件需要继续备份。',
              color: AppColors.amber,
              icon: Icons.warning_amber_rounded,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onContinue,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('继续备份'),
                ),
                if (!dryRun)
                  FilledButton.icon(
                    onPressed: onContinuous,
                    icon: const Icon(Icons.loop_rounded, size: 17),
                    label: const Text('持续备份到所有数据备份完毕'),
                  ),
              ],
            ),
            if (!dryRun) ...[
              const SizedBox(height: 8),
              Text(
                '「继续备份」只再执行一次；「持续备份」会自动重复，直到本次不再达到上限。',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.5,
                  color: AppColors.faint,
                ),
              ),
            ],
          ],
          if (!dryRun) ...[
            const SizedBox(height: 12),
            Text(
              '“提交完成”只代表本地 TargetDir 写入成功；云端副本取决于网盘客户端的同步进度。',
              style: TextStyle(
                fontSize: 11,
                height: 1.55,
                color: AppColors.faint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LockCard extends StatelessWidget {
  const _LockCard({required this.info});

  final TargetLockInfo info;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            info.path,
            style: TextStyle(
              fontFamily: 'Menlo',
              fontSize: 10.5,
              color: AppColors.faint,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'host ${info.hostId ?? '?'} · pid ${info.pid ?? '?'} · '
            'started ${info.startedAt == null ? '?' : formatDateTime(info.startedAt!)}',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          if (info.toolVersion != null)
            Text(
              'tool ${info.toolVersion}',
              style: TextStyle(fontSize: 10.5, color: AppColors.faint),
            ),
          if (info.legacyExists)
            Text(
              '检测到旧版 .apex.lock，也视为写入中。',
              style: TextStyle(fontSize: 10.5, color: AppColors.amber),
            ),
        ],
      ),
    );
  }
}
