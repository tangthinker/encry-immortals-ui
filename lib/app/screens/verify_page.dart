import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../../core/core_exit_code.dart';
import '../../core/core_models.dart';
import '../../core/core_result.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/page_header.dart';
import '../widgets/section_card.dart';

class VerifyPage extends StatefulWidget {
  const VerifyPage({required this.controller, super.key});

  final AppController controller;

  @override
  State<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<VerifyPage> {
  final TextEditingController _sample = TextEditingController(text: '10');
  bool _deep = false;
  bool _runningVerify = false;
  bool _runningDoctor = false;
  VerifySummary? _verify;
  List<DoctorCheck> _checks = [];
  String? _verifyError;
  String? _doctorError;
  CoreExitCode? _verifyExit;
  CoreExitCode? _doctorExit;

  @override
  void dispose() {
    _sample.dispose();
    super.dispose();
  }

  Future<void> _runVerify() async {
    final session = widget.controller.session;
    if (session == null || _runningVerify) return;
    final sample = int.tryParse(_sample.text.trim());
    if (sample == null || sample < 1 || sample > 10000) {
      setState(() => _verifyError = '抽样数量必须是 1..10000 的整数。');
      return;
    }
    setState(() {
      _runningVerify = true;
      _verifyError = null;
      _verifyExit = null;
      _verify = null;
    });
    try {
      final result = await session.verify(sample: sample, deep: _deep);
      if (!mounted) return;
      final summary = result.jsonMap == null
          ? null
          : VerifySummary.fromJson(result.jsonMap!);
      setState(() {
        _runningVerify = false;
        _verify = summary;
        if (!result.isSuccess || summary == null) {
          _verifyExit = result.exit;
          _verifyError = _messageFor(result);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _runningVerify = false;
        _verifyError = '$error';
      });
    }
  }

  Future<void> _runDoctor() async {
    final session = widget.controller.session;
    if (session == null || _runningDoctor) return;
    setState(() {
      _runningDoctor = true;
      _doctorError = null;
      _doctorExit = null;
      _checks = [];
    });
    try {
      final result = await session.doctor(chain: true);
      if (!mounted) return;
      final checks = result.jsonList
              ?.map((item) => DoctorCheck.fromJson(asJsonMap(item)))
              .toList() ??
          const <DoctorCheck>[];
      final failed = checks.any((check) => check.status.isBlocking);
      setState(() {
        _runningDoctor = false;
        _checks = checks;
        if (!result.isSuccess || failed) {
          _doctorExit = result.exit;
          _doctorError = _messageFor(result);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _runningDoctor = false;
        _doctorError = '$error';
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
    final busy = _runningVerify || _runningDoctor || widget.controller.queue.isBusy;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: '校验',
                subtitle: 'verify 检查数据完整性；doctor --chain 检查链、锚点与不变量',
                trailing: StatusPill(
                  label: busy ? '运行中' : '空闲',
                  color: busy ? AppColors.blue : AppColors.faint,
                  dense: true,
                ),
              ),
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  final verify = _VerifyCard(
                    sample: _sample,
                    deep: _deep,
                    busy: busy,
                    running: _runningVerify,
                    onDeep: (value) => setState(() => _deep = value),
                    onRun: _runVerify,
                  );
                  final doctor = _DoctorCard(
                    checks: _checks,
                    busy: busy,
                    running: _runningDoctor,
                    onRun: _runDoctor,
                  );
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: verify),
                        const SizedBox(width: 18),
                        Expanded(child: doctor),
                      ],
                    );
                  }
                  return Column(
                    children: [verify, const SizedBox(height: 16), doctor],
                  );
                },
              ),
              if (_verifyError != null) ...[
                const SizedBox(height: 16),
                NoticeBanner(
                  title: _verifyExit?.label ?? '校验未通过',
                  message: _verifyError!,
                  color: AppColors.danger,
                  icon: Icons.error_outline_rounded,
                ),
              ],
              if (_verify != null) ...[
                const SizedBox(height: 16),
                _VerifyResultCard(summary: _verify!, exitCode: _verifyExit),
              ],
              if (_doctorError != null) ...[
                const SizedBox(height: 16),
                NoticeBanner(
                  title: _doctorExit?.label ?? 'doctor 未通过',
                  message: _doctorError!,
                  color: AppColors.danger,
                  icon: Icons.error_outline_rounded,
                ),
              ],
              if (_checks.isNotEmpty) ...[
                const SizedBox(height: 16),
                _DoctorResultCard(checks: _checks),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VerifyCard extends StatelessWidget {
  const _VerifyCard({
    required this.sample,
    required this.deep,
    required this.busy,
    required this.running,
    required this.onDeep,
    required this.onRun,
  });

  final TextEditingController sample;
  final bool deep;
  final bool busy;
  final bool running;
  final ValueChanged<bool> onDeep;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '完整性校验',
      subtitle: 'verify --sample N / --deep；缺失 pack 返回 13，损坏返回 12',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: sample,
            enabled: !busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '随机抽样 pack 数量',
              helperText: '0 表示不抽样；deep 会全量解密，最慢',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: deep,
            onChanged: busy ? null : onDeep,
            title: const Text(
              '深度校验 --deep',
              style: TextStyle(fontSize: 12.5),
            ),
            subtitle: const Text(
              '全量解密并逐切片校验，等价于不落盘的 restore',
              style: TextStyle(fontSize: 10.5),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: busy ? null : onRun,
            icon: running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF04140D),
                    ),
                  )
                : const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text(running ? '校验中…' : '开始校验'),
          ),
        ],
      ),
    );
  }
}

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({
    required this.checks,
    required this.busy,
    required this.running,
    required this.onRun,
  });

  final List<DoctorCheck> checks;
  final bool busy;
  final bool running;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '一致性自检',
      subtitle: 'doctor --chain：哈希链、锚点、孤儿 pack 与布局',
      trailing: checks.isEmpty
          ? null
          : StatusPill(
              label: checks.any((check) => check.status.isBlocking)
                  ? 'FAIL'
                  : '通过',
              color: checks.any((check) => check.status.isBlocking)
                  ? AppColors.danger
                  : AppColors.accent,
              dense: true,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'doctor 会先校验哈希链与本地锚点，再检查 TargetDir 布局、暂存区与孤儿 pack。',
            style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: busy ? null : onRun,
            icon: running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.health_and_safety_outlined, size: 17),
            label: Text(running ? '自检中…' : '运行 doctor --chain'),
          ),
        ],
      ),
    );
  }
}

class _VerifyResultCard extends StatelessWidget {
  const _VerifyResultCard({required this.summary, required this.exitCode});

  final VerifySummary summary;
  final CoreExitCode? exitCode;

  @override
  Widget build(BuildContext context) {
    final clean = summary.isClean && exitCode == null;
    return SectionCard(
      title: '校验结果',
      subtitle: clean ? '未发现缺失、大小不匹配或抽样失败' : '发现问题；请保留结果并排查',
      accent: clean ? AppColors.accent : AppColors.danger,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              KeyValueChip(
                label: '本地 pack',
                value: '${summary.localPacks}',
              ),
              KeyValueChip(
                label: '引用 pack',
                value: '${summary.referencedPacks}',
              ),
              KeyValueChip(label: '抽样', value: '${summary.sampled}'),
              KeyValueChip(label: '孤儿', value: '${summary.orphans}'),
              KeyValueChip(
                label: '深度文件',
                value: '${summary.deepFiles}',
              ),
              KeyValueChip(
                label: '深度字节',
                value: formatBytes(summary.deepBytes),
              ),
            ],
          ),
          if ((summary.missing ?? []).isNotEmpty) ...[
            const SizedBox(height: 12),
            _IssueList(
              title: '缺失 pack',
              items: summary.missing!,
              color: AppColors.danger,
            ),
          ],
          if ((summary.sizeMismatch ?? []).isNotEmpty) ...[
            const SizedBox(height: 12),
            _IssueList(
              title: '大小不匹配',
              items: summary.sizeMismatch!,
              color: AppColors.danger,
            ),
          ],
          if ((summary.sampleFailures ?? []).isNotEmpty) ...[
            const SizedBox(height: 12),
            _IssueList(
              title: '抽样失败',
              items: summary.sampleFailures!,
              color: AppColors.danger,
            ),
          ],
          if ((summary.deepFailures ?? []).isNotEmpty) ...[
            const SizedBox(height: 12),
            _IssueList(
              title: '深度校验失败',
              items: summary.deepFailures!,
              color: AppColors.danger,
            ),
          ],
          if (clean) ...[
            const SizedBox(height: 10),
            const Text(
              '注意：verify 通过代表本地文件完整，不代表云端没有回滚；需要同时看 doctor 的锚点检查。',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.5,
                color: AppColors.faint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DoctorResultCard extends StatelessWidget {
  const _DoctorResultCard({required this.checks});

  final List<DoctorCheck> checks;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'doctor 结果',
      subtitle: '${checks.length} 项检查',
      child: Column(
        children: [
          for (var index = 0; index < checks.length; index++) ...[
            if (index > 0) const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(
                      checks[index].status.label,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _color(checks[index].status),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 128,
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
                        height: 1.5,
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

  Color _color(DoctorStatus status) => switch (status) {
    DoctorStatus.pass => AppColors.accent,
    DoctorStatus.warn => AppColors.amber,
    DoctorStatus.fail => AppColors.danger,
    _ => AppColors.faint,
  };
}

class _IssueList extends StatelessWidget {
  const _IssueList({
    required this.title,
    required this.items,
    required this.color,
  });

  final String title;
  final List<String> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title（${items.length}）',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        for (final item in items.take(20))
          Text(
            item,
            style: const TextStyle(
              fontFamily: 'Menlo',
              fontSize: 10.5,
              height: 1.5,
              color: AppColors.faint,
            ),
          ),
        if (items.length > 20)
          Text(
            '… 还有 ${items.length - 20} 项',
            style: const TextStyle(fontSize: 10.5, color: AppColors.faint),
          ),
      ],
    );
  }
}
