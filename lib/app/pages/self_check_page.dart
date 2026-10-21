import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/vertical_slice.dart';
import '../bootstrap.dart';
import '../format.dart';
import '../self_check_controller.dart';
import '../theme.dart';
import '../widgets/log_panel.dart';
import '../widgets/page_header.dart';
import '../widgets/section_card.dart';

class SelfCheckPage extends ConsumerWidget {
  const SelfCheckPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(selfCheckProvider);
    final bootstrap = ref.watch(bootstrapProvider);
    final ready = bootstrap.value?.ready ?? false;
    final controller = ref.read(selfCheckProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(36, 30, 36, 52),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: '自检',
                subtitle: '在临时目录跑通真实的 sidecar 链路，不接触任何现有 vault',
                trailing: Wrap(
                  spacing: 10,
                  children: [
                    if (state.hasRun)
                      TextButton.icon(
                        onPressed: state.running ? null : controller.reset,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('重置'),
                      ),
                    if (state.running)
                      OutlinedButton.icon(
                        onPressed: controller.cancel,
                        icon: const Icon(Icons.stop_circle_outlined, size: 17),
                        label: const Text('取消'),
                      ),
                    FilledButton.icon(
                      onPressed: ready && !state.running ? controller.run : null,
                      icon: state.running
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF04140D),
                              ),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 19),
                      label: Text(
                        state.running
                            ? '运行中'
                            : state.hasRun
                            ? '重新运行'
                            : '开始自检',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (!ready && !bootstrap.isLoading)
                Container(
                  margin: const EdgeInsets.only(bottom: 18),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    bootstrap.value?.error ??
                        '核心 sidecar 未就绪，无法运行自检。',
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              _StatusCard(state: state, ready: ready),
              const SizedBox(height: 20),
              SectionCard(
                title: '步骤',
                subtitle: '每一步都使用真实 eimmortal 二进制与独立子进程',
                trailing: Text(
                  '${state.steps.where((step) => step.ok).length}/${state.steps.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.faint,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                child: _StepList(state: state),
              ),
              const SizedBox(height: 20),
              SectionCard(
                title: '运行日志',
                subtitle: 'Armor Key 与密码不会进入日志；只保留命令与进度摘要',
                trailing: Text(
                  '${state.logs.length} 行',
                  style: const TextStyle(fontSize: 11, color: AppColors.faint),
                ),
                child: LogPanel(
                  lines: state.logs,
                  height: 320,
                  emptyText: '运行自检后，这里会显示 13 个步骤的实时日志',
                ),
              ),
              const SizedBox(height: 20),
              const _ScopeCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state, required this.ready});

  final SelfCheckState state;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final (color, icon, title, subtitle) = _content();
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.1),
            AppColors.surface,
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: state.running
                ? Padding(
                    padding: const EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: color,
                    ),
                  )
                : Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: AppColors.muted,
                  ),
                ),
                if (state.running) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      backgroundColor: AppColors.borderSoft,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.currentStep == null
                        ? '准备中…'
                        : '正在执行：${state.currentStep}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.faint,
                    ),
                  ),
                ],
                if (state.report?.workDir != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF070C16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderSoft),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '现场已保留（便于排查）',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.faint,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          state.report!.workDir!,
                          style: const TextStyle(
                            fontFamily: 'Menlo',
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (state.report != null) ...[
            const SizedBox(width: 18),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${state.report!.passed}/${state.report!.steps.length}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  formatDuration(state.report!.duration),
                  style: const TextStyle(fontSize: 11, color: AppColors.faint),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  (Color, IconData, String, String) _content() {
    if (!ready) {
      return (
        AppColors.amber,
        Icons.link_off_rounded,
        '核心未就绪',
        '先解决 sidecar 路径或完整性问题，再运行真实链路。',
      );
    }
    if (state.running) {
      return (
        AppColors.blue,
        Icons.sync_rounded,
        '正在运行 M0 垂直切片',
        'init → backup → log → restore → verify；所有命令严格串行。',
      );
    }
    final report = state.report;
    if (report == null) {
      if (state.error != null) {
        return (AppColors.danger, Icons.error_outline, '自检失败', state.error!);
      }
      return (
        AppColors.faint,
        Icons.science_outlined,
        '尚未运行',
        '点击右上角“开始自检”，用真实 sidecar 验证整条链路。',
      );
    }
    if (report.cancelled) {
      return (
        AppColors.amber,
        Icons.stop_circle_outlined,
        '已取消',
        '临时目录已清理；可以随时重新运行。',
      );
    }
    if (report.success) {
      return (
        AppColors.accent,
        Icons.verified_rounded,
        '全部通过',
        '13 个步骤覆盖创建、备份、历史、密码探针、恢复、抽样校验与 doctor。',
      );
    }
    return (
      AppColors.danger,
      Icons.error_outline_rounded,
      '自检失败',
      report.error ??
          '${report.passed}/${report.steps.length} 步通过；查看下方日志与失败步骤。',
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList({required this.state});

  final SelfCheckState state;

  @override
  Widget build(BuildContext context) {
    if (state.steps.isEmpty && !state.running) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 22),
        child: Center(
          child: Text(
            '还没有步骤结果。运行自检后，每个命令的退出码与耗时都会列在这里。',
            style: TextStyle(fontSize: 12, color: AppColors.faint),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var index = 0; index < state.steps.length; index++)
          _StepRow(index: index + 1, step: state.steps[index]),
        if (state.running)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    state.currentStep ?? '准备下一步…',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Text(
                  '运行中',
                  style: TextStyle(fontSize: 11, color: AppColors.faint),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.step});

  final int index;
  final SliceStep step;

  @override
  Widget build(BuildContext context) {
    final color = step.ok ? AppColors.accent : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Icon(
              step.ok ? Icons.check_rounded : Icons.close_rounded,
              size: 12,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      index.toString().padLeft(2, '0'),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.faint,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        step.title,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  step.detail,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: step.ok ? AppColors.faint : AppColors.danger,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatDuration(step.duration),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.faint,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (step.exitCode != null && step.exitCode != 0)
                Text(
                  'exit ${step.exitCode}${step.ok ? ' · 预期' : ''}',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: step.ok ? AppColors.faint : AppColors.danger,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScopeCard extends StatelessWidget {
  const _ScopeCard();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('会创建什么', '系统临时目录下的一次性 vault、TargetDir、staging 与 3 个测试文件。'),
      ('不会碰什么', '现有 profile、真实 vault、用户目录里的备份。'),
      ('通过标准', '13/13 步通过；恢复内容与源目录逐文件 SHA-256 一致；没有 FAIL。'),
      ('失败时', '保留临时现场并显示路径，方便对照 stderr / 退出码排查。'),
    ];
    return SectionCard(
      title: '自检边界',
      child: Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 94,
                    child: Text(
                      item.$1,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.faint,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.$2,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.55,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
