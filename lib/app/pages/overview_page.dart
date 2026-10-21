import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core_locator.dart';
import '../bootstrap.dart';
import '../self_check_controller.dart';
import '../theme.dart';
import '../widgets/page_header.dart';
import '../widgets/section_card.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({
    required this.onOpenSelfCheck,
    required this.onRunSelfCheck,
    super.key,
  });

  final VoidCallback onOpenSelfCheck;
  final VoidCallback onRunSelfCheck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(bootstrapProvider);
    final selfCheck = ref.watch(selfCheckProvider);
    final info = bootstrap.value;

    final coreStatus = info == null
        ? const StatusPill(label: '正在定位核心', color: AppColors.amber)
        : info.ready
        ? StatusPill(
            label: '核心就绪 · ${info.version ?? 'unknown'}',
            color: AppColors.accent,
          )
        : const StatusPill(label: '核心不可用', color: AppColors.danger);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(36, 30, 36, 52),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: '概览',
                subtitle: '本地优先的加密增量备份控制台 · M0 垂直切片阶段',
                trailing: coreStatus,
              ),
              const SizedBox(height: 26),
              if (bootstrap.isLoading)
                const _LoadingHero()
              else if (info != null && !info.ready)
                _ErrorHero(info: info)
              else
                _Hero(
                  version: info?.version,
                  running: selfCheck.running,
                  onRun: selfCheck.running ? null : onRunSelfCheck,
                  onOpen: onOpenSelfCheck,
                ),
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 880;
                  final environment = _EnvironmentCard(bootstrap: bootstrap);
                  final milestones = _MilestonesCard(
                    selfCheck: selfCheck,
                    onOpen: onOpenSelfCheck,
                  );
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 11, child: environment),
                        const SizedBox(width: 20),
                        Expanded(flex: 10, child: milestones),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      environment,
                      const SizedBox(height: 20),
                      milestones,
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              const _NextStepsCard(),
              const SizedBox(height: 22),
              const _SecurityCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.version,
    required this.running,
    required this.onRun,
    required this.onOpen,
  });

  final String? version;
  final bool running;
  final VoidCallback? onRun;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.24)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10261F), Color(0xFF0C1524)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -60,
            top: -90,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0.16),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 26, 30, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const StatusPill(
                      label: 'M0 · SIDECAR VERTICAL SLICE',
                      color: AppColors.accent,
                      dense: true,
                    ),
                    const SizedBox(width: 10),
                    if (version != null)
                      Text(
                        'eimmortal $version',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.faint,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  '把加密备份链，\n装进一个安静的桌面窗口。',
                  style: TextStyle(
                    fontSize: 30,
                    height: 1.22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 12),
                const SizedBox(
                  width: 620,
                  child: Text(
                    'Flutter 只负责收集参数、展示结果与串行调度；加密、打包与链校验全部交给固定版本的 Go sidecar。'
                    '当前构建先跑通 init → backup → log → restore → verify 的真实链路。',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.7,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: onRun,
                      icon: running
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF04140D),
                              ),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 19),
                      label: Text(running ? '自检运行中' : '运行垂直切片自检'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.terminal_rounded, size: 18),
                      label: const Text('查看自检日志'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: AppColors.faint,
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '自检会在系统临时目录创建一次性 vault，解锁峰值内存约 1.1 GB，结束后自动清理。',
                        style: TextStyle(fontSize: 11.5, color: AppColors.faint),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingHero extends StatelessWidget {
  const _LoadingHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
            SizedBox(height: 14),
            Text(
              '正在定位 sidecar 并读取核心版本…',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorHero extends StatelessWidget {
  const _ErrorHero({required this.info});

  final BootstrapInfo info;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.danger),
              SizedBox(width: 8),
              Text(
                '无法启动核心 sidecar',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            info.error ?? '未知错误',
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '开发模式可设置 EIMMORTAL_CORE_PATH 指向本地上游二进制，例如：',
            style: TextStyle(fontSize: 12, color: AppColors.faint),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF070C16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderSoft),
            ),
            child: const SelectableText(
              'EIMMORTAL_CORE_PATH=/path/to/encry-immortals/bin/eimmortal \\\n'
              '  flutter run -d macos',
              style: TextStyle(
                fontFamily: 'Menlo',
                fontSize: 11.5,
                color: AppColors.muted,
                height: 1.6,
              ),
            ),
          ),
          if (info.searchedPaths.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '已查找：${info.searchedPaths.join('、')}',
              style: const TextStyle(fontSize: 11, color: AppColors.faint),
            ),
          ],
        ],
      ),
    );
  }
}

class _EnvironmentCard extends StatelessWidget {
  const _EnvironmentCard({required this.bootstrap});

  final AsyncValue<BootstrapInfo> bootstrap;

  @override
  Widget build(BuildContext context) {
    final info = bootstrap.value;
    return SectionCard(
      title: '运行环境',
      subtitle: 'sidecar 路径、完整性与版本必须一起核对',
      trailing: info == null
          ? null
          : StatusPill(
              label: info.integrityLabel,
              color: info.integrity?.status == CoreIntegrityStatus.verified
                  ? AppColors.accent
                  : info.integrityOk
                  ? AppColors.amber
                  : AppColors.danger,
              dense: true,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(
            label: '核心版本',
            value: info?.version ?? (bootstrap.isLoading ? '读取中…' : '不可用'),
            mono: true,
          ),
          const Divider(),
          InfoRow(
            label: 'sidecar',
            value: info?.binary?.path ?? '未找到',
            mono: true,
            selectable: true,
            valueColor: info?.binary == null ? AppColors.danger : null,
          ),
          const Divider(),
          InfoRow(label: '来源', value: info?.sourceLabel ?? '—'),
          const Divider(),
          InfoRow(
            label: '完整性',
            value: info?.integrityLabel ?? '—',
            valueColor: info?.integrityOk == false ? AppColors.danger : null,
          ),
          const Divider(),
          InfoRow(
            label: 'SHA-256',
            value: info?.integrity?.actualSha256 ?? '—',
            mono: true,
            valueColor: AppColors.faint,
          ),
          if (info?.error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                info!.error!,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: AppColors.danger,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MilestonesCard extends ConsumerWidget {
  const _MilestonesCard({required this.selfCheck, required this.onOpen});

  final SelfCheckState selfCheck;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sliceLabel = selfCheck.running
        ? '运行中'
        : selfCheck.report?.success == true
        ? '最近通过'
        : selfCheck.report != null
        ? '最近失败'
        : '待运行';
    final sliceColor = selfCheck.running
        ? AppColors.blue
        : selfCheck.report?.success == true
        ? AppColors.accent
        : selfCheck.report != null
        ? AppColors.danger
        : AppColors.faint;

    return SectionCard(
      title: 'M0 进度',
      subtitle: '先验证底座，再做漂亮页面',
      child: Column(
        children: [
          const _MilestoneRow(
            label: 'Flutter 桌面脚手架',
            detail: 'macOS / Windows 工程已生成',
            done: true,
          ),
          const _MilestoneRow(
            label: 'CoreGateway',
            detail: '进程 IO · JSON · 退出码映射',
            done: true,
          ),
          const _MilestoneRow(
            label: '串行命令队列',
            detail: '单飞 · 取消 · 不阻塞后续任务',
            done: true,
          ),
          _MilestoneRow(
            label: '垂直切片 13 步',
            detail: 'init → backup → log → restore → verify',
            done: selfCheck.report?.success == true,
            color: sliceColor,
            trailing: sliceLabel,
            onTap: onOpen,
          ),
          const _MilestoneRow(
            label: 'Onboarding / 仪表盘',
            detail: 'M1：创建库、加入库、解锁',
            done: false,
            color: AppColors.blue,
            trailing: '下一步',
          ),
        ],
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({
    required this.label,
    required this.detail,
    required this.done,
    this.color,
    this.trailing,
    this.onTap,
  });

  final String label;
  final String detail;
  final bool done;
  final Color? color;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ??
        (done ? AppColors.accent : AppColors.faint);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: effectiveColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: effectiveColor.withValues(alpha: 0.4),
                ),
              ),
              child: Icon(
                done ? Icons.check_rounded : Icons.circle_outlined,
                size: 12,
                color: effectiveColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.faint,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: TextStyle(
                  fontSize: 11,
                  color: effectiveColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NextStepsCard extends StatelessWidget {
  const _NextStepsCard();

  @override
  Widget build(BuildContext context) {
    const steps = [
      ('Onboarding', '选择源目录与 TargetDir，创建新库；或加入已有库并导入 Armor Key。'),
      ('解锁与仪表盘', '用 log 做密码探针，用 status --chain 刷新健康度；区分“未解锁”与“真回滚”。'),
      ('备份与历史', 'dry-run、流式进度、截断提示；log → show → ls 的懒加载浏览。'),
      ('恢复与校验', '恢复前强制 doctor --chain；展示缺失 pack，禁止静默忽略回滚风险。'),
    ];
    return SectionCard(
      title: '下一里程碑 · M1',
      subtitle: '错误码、锁与恢复安全优先于动画和图表',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final children = <Widget>[];
          for (var index = 0; index < steps.length; index++) {
            children.add(
              _NextStep(index: index + 1, title: steps[index].$1, body: steps[index].$2),
            );
          }
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  if (index > 0) const SizedBox(width: 14),
                  Expanded(child: children[index]),
                ],
              ],
            );
          }
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) const SizedBox(height: 12),
                children[index],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _NextStep extends StatelessWidget {
  const _NextStep({
    required this.index,
    required this.title,
    required this.body,
  });

  final int index;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '0$index',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.blue,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.55,
              color: AppColors.faint,
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('主密码', '只经 stdin 管道，不写 argv / env / 临时文件 / 日志。'),
      ('并发', '所有命令串行，避免双解锁与 E20 控制锁冲突。'),
      ('恢复', 'restore 前先 doctor --chain；FAIL 时禁止自动继续。'),
      ('产物', 'sidecar 随包签名并固定 SHA-256，开发期才允许路径覆盖。'),
    ];
    return SectionCard(
      title: '安全边界',
      subtitle: '客户端不实现任何加密、索引或 pack/journal 逻辑',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final cards = [
            for (final item in items)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderSoft),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 16,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.$1,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.$2,
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.55,
                              color: AppColors.faint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ];
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < cards.length; index++) ...[
                  if (index > 0) const SizedBox(width: 12),
                  Expanded(child: cards[index]),
                ],
              ],
            );
          }
          return Column(
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                if (index > 0) const SizedBox(height: 10),
                cards[index],
              ],
            ],
          );
        },
      ),
    );
  }
}
