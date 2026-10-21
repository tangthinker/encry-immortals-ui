import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_controller.dart';
import '../../core/core_exit_code.dart';
import '../../core/core_models.dart';
import '../../core/core_result.dart';
import '../../core/profile.dart';
import '../../core/progress.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/log_panel.dart';
import '../widgets/page_header.dart';
import '../widgets/section_card.dart';

class RestorePage extends StatefulWidget {
  const RestorePage({required this.controller, super.key});

  final AppController controller;

  @override
  State<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends State<RestorePage> {
  final TextEditingController _destination = TextEditingController();
  final TextEditingController _waitSeconds = TextEditingController(text: '120');
  List<CommitEntry> _commits = [];
  bool _loadingHistory = true;
  String? _historyError;
  int? _selectedSeq;
  String _overwrite = 'never';
  bool _skipMissing = false;
  bool _waitForPacks = false;
  bool _running = false;
  bool _dryRun = false;
  String? _error;
  CoreExitCode? _exitCode;
  List<String> _logs = [];
  CoreProgress? _progress;
  List<DoctorCheck> _doctorChecks = [];
  List<PackRef> _packs = [];
  RestoreSummary? _summary;
  int _revision = -1;

  @override
  void initState() {
    super.initState();
    _revision = widget.controller.dataRevision;
    widget.controller.addListener(_onControllerChanged);
    _loadHistory();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _destination.dispose();
    _waitSeconds.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (widget.controller.dataRevision == _revision) return;
    _revision = widget.controller.dataRevision;
    if (mounted) _loadHistory(keepSelection: true);
  }

  Future<void> _loadHistory({bool keepSelection = false}) async {
    final session = widget.controller.session;
    if (session == null) return;
    final previous = keepSelection ? _selectedSeq : null;
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    final result = await session.history();
    if (!mounted) return;
    if (!result.isSuccess || result.jsonList == null) {
      setState(() {
        _loadingHistory = false;
        _historyError =
            '${result.exit.label}（exit ${result.exitCode}）\n${result.errorSummary}';
      });
      return;
    }
    final commits = result.jsonList!
        .map((item) => CommitEntry.fromJson(asJsonMap(item)))
        .toList()
      ..sort((a, b) => b.seq.compareTo(a.seq));
    setState(() {
      _commits = commits;
      _loadingHistory = false;
      _historyError = null;
      _selectedSeq = previous != null &&
              commits.any((commit) => commit.seq == previous)
          ? previous
          : commits.isEmpty
          ? null
          : commits.first.seq;
    });
  }

  Future<void> _pickDestination() async {
    final path = await getDirectoryPath(
      confirmButtonText: '选择恢复目标',
    );
    if (path == null || !mounted) return;
    setState(() => _destination.text = path);
  }

  String? _destinationError(Profile? profile) {
    final value = _destination.text.trim();
    if (value.isEmpty) return '请选择或输入恢复目标目录。';
    if (!p.isAbsolute(value)) return '恢复目标必须是绝对路径。';
    if (profile != null) {
      final dest = p.canonicalize(value);
      final target = p.canonicalize(profile.targetDir);
      final source = p.canonicalize(profile.sourceRoot);
      if (p.equals(dest, target) ||
          p.isWithin(target, dest) ||
          p.isWithin(dest, target)) {
        return '恢复目标不能与 TargetDir 相同或互相包含。';
      }
      if (p.equals(dest, source) ||
          p.isWithin(source, dest) ||
          p.isWithin(dest, source)) {
        return '恢复目标不能覆盖源目录。';
      }
    }
    final existing = FileSystemEntity.typeSync(value);
    if (existing == FileSystemEntityType.file) {
      return '恢复目标是一个文件，不是目录。';
    }
    if (existing == FileSystemEntityType.notFound) {
      final parent = Directory(p.dirname(value));
      if (!parent.existsSync()) return '恢复目标的父目录不存在。';
    }
    return null;
  }

  Future<void> _execute({required bool dryRun}) async {
    if (_running) return;
    final session = widget.controller.session;
    final profile = widget.controller.profile;
    final seq = _selectedSeq;
    if (session == null || profile == null || seq == null) return;
    final destError = _destinationError(profile);
    if (destError != null) {
      setState(() {
        _error = destError;
        _exitCode = null;
      });
      return;
    }
    int? waitSeconds;
    if (_waitForPacks) {
      waitSeconds = int.tryParse(_waitSeconds.text.trim());
      if (waitSeconds == null || waitSeconds < 1 || waitSeconds > 3600) {
        setState(() => _error = '等待时间必须是 1..3600 秒。');
        return;
      }
    }
    if (_overwrite == 'always' && !dryRun) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('确认覆盖已有文件？'),
          content: const Text(
            '--overwrite always 会覆盖目标目录中已存在的文件，且不保留冲突副本。'
            '请确认目标目录选择正确。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('仍然恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _running = true;
      _dryRun = dryRun;
      _error = null;
      _exitCode = null;
      _logs = [];
      _progress = null;
      _doctorChecks = [];
      _packs = [];
      _summary = null;
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

    try {
      final doctor = await session.doctor(chain: true, onStderr: onStderr);
      if (!mounted) return;
      final checks = doctor.jsonList
              ?.map((item) => DoctorCheck.fromJson(asJsonMap(item)))
              .toList() ??
          const <DoctorCheck>[];
      final doctorFailed =
          !doctor.isSuccess || checks.any((check) => check.status.isBlocking);
      setState(() => _doctorChecks = checks);
      if (doctorFailed) {
        setState(() {
          _running = false;
          _exitCode = doctor.exit;
          _error =
              '恢复前 doctor --chain 未通过，已停止。请先在“校验”页处理 FAIL 项。\n'
              '${doctor.errorSummary}';
        });
        return;
      }

      final packsResult = await session.restore(
        destination: _destination.text.trim(),
        seq: seq,
        listPacks: true,
        onStderr: onStderr,
      );
      if (!mounted) return;
      final packs = packsResult.jsonList
              ?.map((item) => PackRef.fromJson(asJsonMap(item)))
              .toList() ??
          const <PackRef>[];
      setState(() => _packs = packs);
      if (!packsResult.isSuccess) {
        setState(() {
          _running = false;
          _exitCode = packsResult.exit;
          _error =
              '读取所需 pack 失败：${packsResult.errorSummary}';
        });
        return;
      }
      final missing = packs.where((pack) => !pack.present).toList();
      if (missing.isNotEmpty && !_skipMissing && !_waitForPacks) {
        setState(() {
          _running = false;
          _error =
              '缺少 ${missing.length} 个 pack。请先等待网盘同步，或明确勾选“跳过缺失 pack”/“等待同步”。';
        });
        return;
      }

      final result = await session.restore(
        destination: _destination.text.trim(),
        seq: seq,
        overwrite: _overwrite,
        dryRun: dryRun,
        skipMissingPacks: _skipMissing,
        waitForPacks: waitSeconds == null
            ? null
            : Duration(seconds: waitSeconds),
        onStderr: onStderr,
      );
      if (!mounted) return;
      final summary = result.jsonMap == null
          ? null
          : RestoreSummary.fromJson(result.jsonMap!);
      if (result.isSuccess && summary == null) {
        setState(() {
          _running = false;
          _progress = null;
          _error = '恢复返回成功，但 JSON 结构无法解析（协议漂移）。';
        });
        return;
      }
      if (summary != null) {
        setState(() {
          _running = false;
          _summary = summary;
          _progress = null;
          if (!result.isSuccess) {
            _exitCode = result.exit;
            _error = _messageFor(result);
          }
        });
        return;
      }
      setState(() {
        _running = false;
        _progress = null;
        _exitCode = result.exit;
        _error = _messageFor(result);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _progress = null;
        _error = '$error';
      });
    }
  }

  String _messageFor(CoreResult result) {
    final summary = result.errorSummary;
    final extra = summary == result.exit.label ? '' : '\n$summary';
    return '${result.exit.label}（exit ${result.exitCode}）· '
        '${result.exit.guidance}$extra';
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.controller.profile;
    final busy = _running || widget.controller.queue.isBusy;
    final hasCommits = _commits.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: '恢复',
                subtitle: '恢复前强制 doctor --chain，并检查缺失 pack；云端回滚风险需自行确认',
                trailing: StatusPill(
                  label: _running ? '恢复中' : '空闲',
                  color: _running ? AppColors.blue : AppColors.faint,
                  dense: true,
                ),
              ),
              const SizedBox(height: 22),
              if (_historyError != null) ...[
                NoticeBanner(
                  title: '读取历史失败',
                  message: _historyError!,
                  color: AppColors.danger,
                ),
                const SizedBox(height: 14),
              ],
              SectionCard(
                title: '恢复参数',
                subtitle: '目标目录不会自动清空；已存在文件由覆盖策略决定',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '快照',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedSeq,
                      isExpanded: true,
                      items: [
                        for (final commit in _commits)
                          DropdownMenuItem(
                            value: commit.seq,
                            child: Text(
                              'seq ${commit.seq} · ${formatDateTime(commit.timestamp)}'
                              '${commit.message.isEmpty ? '' : ' · ${commit.message}'}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Menlo',
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                      ],
                      onChanged: busy || !hasCommits
                          ? null
                          : (value) => setState(() => _selectedSeq = value),
                      decoration: InputDecoration(
                        hintText: _loadingHistory
                            ? '读取历史中…'
                            : hasCommits
                            ? '选择快照'
                            : '还没有可恢复的提交',
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '恢复到',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _destination,
                            enabled: !busy,
                            style: const TextStyle(
                              fontFamily: 'Menlo',
                              fontSize: 11.5,
                            ),
                            decoration: const InputDecoration(
                              hintText: '/path/to/restore（可以是尚不存在的目录）',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: busy ? null : _pickDestination,
                          child: const Text('选择…'),
                        ),
                      ],
                    ),
                    if (profile != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '不要选择 TargetDir（${profile.targetDir}）或源目录本身。',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.faint,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _overwrite,
                            items: const [
                              DropdownMenuItem(
                                value: 'never',
                                child: Text('跳过已存在文件（默认）'),
                              ),
                              DropdownMenuItem(
                                value: 'if-changed',
                                child: Text('内容不同才覆盖'),
                              ),
                              DropdownMenuItem(
                                value: 'always',
                                child: Text('全部覆盖（危险）'),
                              ),
                            ],
                            onChanged: busy
                                ? null
                                : (value) => setState(
                                    () => _overwrite = value ?? 'never',
                                  ),
                            decoration: const InputDecoration(
                              labelText: '覆盖策略',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _skipMissing,
                            onChanged: busy
                                ? null
                                : (value) => setState(() {
                                    _skipMissing = value;
                                    if (value) _waitForPacks = false;
                                  }),
                            title: const Text(
                              '跳过缺失 pack',
                              style: TextStyle(fontSize: 12.5),
                            ),
                            subtitle: const Text(
                              '先恢复已同步的部分',
                              style: TextStyle(fontSize: 10.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _waitForPacks,
                      onChanged: busy
                          ? null
                          : (value) => setState(() {
                              _waitForPacks = value;
                              if (value) _skipMissing = false;
                            }),
                      title: const Text(
                        '缺失 pack 时等待同步',
                        style: TextStyle(fontSize: 12.5),
                      ),
                      subtitle: const Text(
                        '等待期间保持命令运行；超时后按 CLI 语义结束',
                        style: TextStyle(fontSize: 10.5),
                      ),
                    ),
                    if (_waitForPacks)
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 16),
                        child: TextField(
                          controller: _waitSeconds,
                          enabled: !busy,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '最长等待秒数',
                            isDense: true,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: busy || !hasCommits || _selectedSeq == null
                              ? null
                              : () => _execute(dryRun: true),
                          icon: const Icon(Icons.preview_outlined, size: 16),
                          label: const Text('预演'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: busy || !hasCommits || _selectedSeq == null
                              ? null
                              : () => _execute(dryRun: false),
                          icon: busy
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF04140D),
                                  ),
                                )
                              : const Icon(Icons.restore_rounded, size: 17),
                          label: Text(busy ? '运行中…' : '开始恢复'),
                        ),
                        const Spacer(),
                        const Text(
                          'doctor --chain 是硬性前置',
                          style: TextStyle(fontSize: 10.5, color: AppColors.faint),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_running) ...[
                const SizedBox(height: 18),
                SectionCard(
                  title: _dryRun ? '正在预演恢复' : '正在恢复',
                  subtitle: '恢复会先校验链，再按 pack 清单解密写入目标目录',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          minHeight: 5,
                          value: _progress == null
                              ? null
                              : _progress!.percent / 100,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _progress == null
                            ? '正在执行预检…'
                            : '${_progress!.doneFiles}/${_progress!.totalFiles} 文件 · '
                                  '${_progress!.percent}%',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.muted,
                        ),
                      ),
                      if (_progress?.current != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _progress!.current!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Menlo',
                            fontSize: 10.5,
                            color: AppColors.faint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (_doctorChecks.isNotEmpty) ...[
                const SizedBox(height: 18),
                _DoctorCard(checks: _doctorChecks),
              ],
              if (_packs.isNotEmpty) ...[
                const SizedBox(height: 18),
                _PacksCard(packs: _packs),
              ],
              if (_summary != null) ...[
                const SizedBox(height: 18),
                _RestoreResultCard(summary: _summary!),
              ],
              if (_error != null) ...[
                const SizedBox(height: 18),
                NoticeBanner(
                  title: _exitCode?.label ?? '恢复未完成',
                  message: _error!,
                  color: AppColors.danger,
                  icon: Icons.error_outline_rounded,
                ),
              ],
              if (_logs.isNotEmpty) ...[
                const SizedBox(height: 18),
                SectionCard(
                  title: '运行日志',
                  subtitle: '只保留在内存中',
                  child: LogPanel(lines: _logs, height: 240),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({required this.checks});

  final List<DoctorCheck> checks;

  @override
  Widget build(BuildContext context) {
    final fail = checks.where((check) => check.status.isBlocking).length;
    return SectionCard(
      title: '安全预检 · doctor --chain',
      subtitle: '恢复前必须通过；FAIL 会阻止恢复',
      trailing: StatusPill(
        label: fail == 0 ? '通过' : '$fail FAIL',
        color: fail == 0 ? AppColors.accent : AppColors.danger,
        dense: true,
      ),
      child: Column(
        children: [
          for (var index = 0; index < checks.length; index++) ...[
            if (index > 0) const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    checks[index].status == DoctorStatus.pass
                        ? Icons.check_circle_outline_rounded
                        : checks[index].status == DoctorStatus.fail
                        ? Icons.error_outline_rounded
                        : Icons.info_outline_rounded,
                    size: 14,
                    color: checks[index].status == DoctorStatus.pass
                        ? AppColors.accent
                        : checks[index].status == DoctorStatus.fail
                        ? AppColors.danger
                        : AppColors.amber,
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    child: Text(
                      checks[index].name,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      checks[index].detail,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.faint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PacksCard extends StatelessWidget {
  const _PacksCard({required this.packs});

  final List<PackRef> packs;

  @override
  Widget build(BuildContext context) {
    final missing = packs.where((pack) => !pack.present).toList();
    return SectionCard(
      title: '所需 pack',
      subtitle: '来自 restore --list-packs；缺失项需要等待网盘同步',
      trailing: StatusPill(
        label: missing.isEmpty ? '齐全' : '缺失 ${missing.length}',
        color: missing.isEmpty ? AppColors.accent : AppColors.danger,
        dense: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${packs.length} 个 pack · '
            '${formatBytes(packs.fold(0, (sum, pack) => sum + pack.size))}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final pack in missing)
              Text(
                pack.path.isEmpty ? pack.name : pack.path,
                style: const TextStyle(
                  fontFamily: 'Menlo',
                  fontSize: 10.5,
                  color: AppColors.danger,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _RestoreResultCard extends StatelessWidget {
  const _RestoreResultCard({required this.summary});

  final RestoreSummary summary;

  @override
  Widget build(BuildContext context) {
    final incomplete = summary.incomplete;
    return SectionCard(
      title: summary.dryRun ? '预演结果' : '恢复完成',
      subtitle: summary.dryRun
          ? '未写入目标目录'
          : '目标目录写入完成；请自行检查缺失项',
      accent: incomplete ? AppColors.amber : AppColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              KeyValueChip(label: 'seq', value: '${summary.seq}'),
              KeyValueChip(label: '文件', value: '${summary.files}'),
              KeyValueChip(label: '目录', value: '${summary.dirs}'),
              KeyValueChip(label: '链接', value: '${summary.links}'),
              KeyValueChip(label: '字节', value: formatBytes(summary.bytes)),
              if ((summary.skipped ?? []).isNotEmpty)
                KeyValueChip(
                  label: '跳过',
                  value: '${summary.skipped!.length}',
                ),
            ],
          ),
          if (incomplete) ...[
            const SizedBox(height: 12),
            NoticeBanner(
              title: '恢复不完整',
              message: '存在缺失 pack 或文件；这不是完整快照。请等待同步后重试，或确认接受部分恢复。',
              color: AppColors.amber,
              icon: Icons.warning_amber_rounded,
            ),
          ],
          if ((summary.corrupt ?? []).isNotEmpty) ...[
            const SizedBox(height: 12),
            NoticeBanner(
              title: '检测到损坏文件',
              message: (summary.corrupt ?? []).join('\n'),
              color: AppColors.danger,
              icon: Icons.error_outline_rounded,
            ),
          ],
          if ((summary.missingPacks ?? []).isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '缺失 pack：${(summary.missingPacks ?? []).join('、')}',
              style: const TextStyle(fontSize: 10.5, color: AppColors.faint),
            ),
          ],
        ],
      ),
    );
  }
}
