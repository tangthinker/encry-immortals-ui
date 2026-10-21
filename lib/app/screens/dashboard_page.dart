import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_controller.dart';
import '../../core/core_models.dart';
import '../../core/profile.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/chain_seal.dart';
import '../widgets/page_header.dart';
import '../widgets/section_card.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    required this.controller,
    required this.onNavigate,
    super.key,
  });

  final AppController controller;
  final ValueChanged<int> onNavigate;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  VaultStatus? _status;
  List<CommitEntry> _commits = [];
  bool _loading = true;
  String? _error;
  int _revision = -1;
  int _refreshRevision = -1;

  @override
  void initState() {
    super.initState();
    _revision = widget.controller.dataRevision;
    _refreshRevision = widget.controller.refreshRevision;
    widget.controller.addListener(_onControllerChanged);
    _load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final dataChanged = widget.controller.dataRevision != _revision;
    final refresh = widget.controller.refreshRevision != _refreshRevision;
    if (!dataChanged && !refresh) return;
    _revision = widget.controller.dataRevision;
    _refreshRevision = widget.controller.refreshRevision;
    if (mounted) _load(quiet: true);
  }

  Future<void> _load({bool quiet = false}) async {
    final session = widget.controller.session;
    if (session == null) return;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final statusResult = await session.status(chain: true);
      if (!mounted) return;
      if (!statusResult.isSuccess || statusResult.jsonMap == null) {
        setState(() {
          _loading = false;
          _error =
              '${statusResult.exit.label}（exit ${statusResult.exitCode}）\n'
              '${statusResult.exit.guidance}\n${statusResult.errorSummary}';
        });
        return;
      }
      final status = VaultStatus.fromJson(statusResult.jsonMap!);
      await widget.controller.refreshTargetLock();
      if (!mounted) return;
      final historyResult = await session.history();
      if (!mounted) return;
      final commits = historyResult.jsonList
              ?.map((item) => CommitEntry.fromJson(asJsonMap(item)))
              .toList() ??
          const <CommitEntry>[];
      commits.sort((a, b) => b.seq.compareTo(a.seq));
      setState(() {
        _status = status;
        _commits = commits;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.controller.profile;
    final status = _status;
    final latest = _commits.isEmpty ? null : _commits.first;
    final targetMissing = profile != null && !profile.targetExists;
    final sourceMissing = profile != null && !profile.sourceExists;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: '概览',
                subtitle: profile == null
                    ? '未配置'
                    : '${profile.mode.label} · ${p.basename(profile.targetDir)}',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: _loading ? null : () => _load(),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('刷新'),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(
                      label: _loading
                          ? '刷新中'
                          : status?.isHealthy == true
                          ? '健康'
                          : status == null
                          ? '不可用'
                          : '需注意',
                      color: _loading
                          ? AppColors.blue
                          : status?.isHealthy == true
                          ? AppColors.success
                          : AppColors.amber,
                      dense: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              if (targetMissing || sourceMissing) ...[
                NoticeBanner(
                  title: '目录不可访问',
                  message: [
                    if (sourceMissing) '源目录不存在：${profile.sourceRoot}',
                    if (targetMissing) 'TargetDir 不存在：${profile.targetDir}',
                  ].join('\n'),
                  color: AppColors.danger,
                  icon: Icons.folder_off_outlined,
                ),
                const SizedBox(height: 16),
              ],
              if (_error != null) ...[
                NoticeBanner(
                  title: '读取状态失败',
                  message: _error!,
                  color: AppColors.danger,
                  icon: Icons.error_outline_rounded,
                  action: TextButton(
                    onPressed: _loading ? null : () => _load(),
                    child: const Text('重试'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_loading && status == null)
                const _LoadingCard()
              else if (status != null) ...[
                _MetricsGrid(status: status, latest: latest),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final health = _HealthCard(
                      status: status,
                      onVerify: () => widget.onNavigate(4),
                    );
                    final latestCard = _LatestCommitCard(
                      commit: latest,
                      onHistory: () => widget.onNavigate(2),
                      onBackup: () => widget.onNavigate(1),
                    );
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 11, child: health),
                          const SizedBox(width: 18),
                          Expanded(flex: 10, child: latestCard),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        health,
                        const SizedBox(height: 16),
                        latestCard,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                _PathsCard(
                  profile: profile,
                  onBackup: () => widget.onNavigate(1),
                  onRestore: () => widget.onNavigate(3),
                  onVerify: () => widget.onNavigate(4),
                ),
              ] else
                _EmptyCard(onRetry: () => _load()),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return  SectionCard(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(height: 12),
              Text(
                '正在读取状态与历史…',
                style: TextStyle(fontSize: 12, color: AppColors.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: EmptyState(
        icon: Icons.cloud_off_outlined,
        title: '还没有可展示的状态',
        message: '检查 TargetDir 是否可访问，然后重试。',
        action: OutlinedButton(
          onPressed: onRetry,
          child: const Text('重试'),
        ),
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.status, required this.latest});

  final VaultStatus status;
  final CommitEntry? latest;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      (
        '最近提交',
        status.lastSeq == 0 ? '尚无' : 'seq ${status.lastSeq}',
        latest == null ? '还没有备份记录' : formatDateTime(latest!.timestamp),
        Icons.commit_rounded,
        AppColors.accent,
      ),
      (
        '本地 packs',
        '${status.localPacks}',
        '引用 ${status.referencedPacks} · 缺失 ${status.missingPacks}',
        Icons.inventory_2_outlined,
        AppColors.blue,
      ),
      (
        '密文体积',
        formatBytes(status.packTotalBytes),
        '逻辑源 ${formatBytes(status.logicalSourceBytes)}',
        Icons.storage_rounded,
        AppColors.violet,
      ),
      (
        '链状态',
        status.verified ? '已验证' : '未验证',
        '锚点 ${status.anchorShort.isEmpty ? '—' : status.anchorShort}',
        status.verified ? Icons.verified_rounded : Icons.gpp_bad_outlined,
        status.verified ? AppColors.success : AppColors.amber,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 4 : 2;
        final spacing = 14.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: _MetricCard(
                  label: metric.$1,
                  value: metric.$2,
                  detail: metric.$3,
                  icon: metric.$4,
                  color: metric.$5,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 7),
              Text(
                label,
                style:  TextStyle(fontSize: 11, color: AppColors.faint),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:  TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:  TextStyle(fontSize: 10.5, color: AppColors.faint),
          ),
        ],
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.status, required this.onVerify});

  final VaultStatus status;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final warnings = status.warnings;
    final healthy = status.isHealthy && !status.hasUnlockWarning;
    return SectionCard(
      title: '健康度',
      subtitle: healthy
          ? '以 CLI 的 status --chain 为准 · 正常'
          : '以 CLI 的 status --chain 为准 · 需注意',
      trailing: ChainSeal(
        anchor: status.anchorShort,
        verified: healthy,
        size: 78,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(
            label: 'vault_id',
            value: status.vaultId.isEmpty ? '—' : status.vaultId,
            mono: true,
          ),
          const Divider(),
          InfoRow(
            label: 'packs',
            value:
                'local ${status.localPacks} · referenced ${status.referencedPacks} · '
                'orphan ${status.orphanPacks} · missing ${status.missingPacks}',
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 14),
            NoticeBanner(
              message: warnings.join('\n'),
              color: status.hasUnlockWarning ? AppColors.danger : AppColors.amber,
              title: '提醒',
            ),
          ],
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onVerify,
              icon: const Icon(Icons.verified_outlined, size: 16),
              label: const Text('运行校验'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LatestCommitCard extends StatelessWidget {
  const _LatestCommitCard({
    required this.commit,
    required this.onHistory,
    required this.onBackup,
  });

  final CommitEntry? commit;
  final VoidCallback onHistory;
  final VoidCallback onBackup;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '最近一次提交',
      subtitle: commit == null ? '还没有备份历史' : formatDateTime(commit!.timestamp),
      child: commit == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 Text(
                  '创建库后还没有提交。先做一次备份，历史记录会出现在这里。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: AppColors.faint,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onBackup,
                  icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                  label: const Text('开始备份'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  commit!.message.isEmpty ? '（无提交信息）' : commit!.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:  TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    KeyValueChip(label: 'seq', value: '${commit!.seq}'),
                    KeyValueChip(label: 'ops', value: '${commit!.ops}'),
                    KeyValueChip(label: 'dirs', value: '${commit!.dirs}'),
                    KeyValueChip(label: 'packs', value: '${commit!.packs}'),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: onHistory,
                      child: const Text('查看历史'),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: onBackup,
                      child: const Text('再次备份'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _PathsCard extends StatelessWidget {
  const _PathsCard({
    required this.profile,
    required this.onBackup,
    required this.onRestore,
    required this.onVerify,
  });

  final Profile? profile;
  final VoidCallback onBackup;
  final VoidCallback onRestore;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '路径与快捷操作',
      subtitle: '源根目录在创建 profile 时固定',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(
            label: '源目录',
            value: profile?.sourceRoot ?? '—',
            mono: true,
            selectable: true,
          ),
          const Divider(),
          InfoRow(
            label: 'TargetDir',
            value: profile?.targetDir ?? '—',
            mono: true,
            selectable: true,
          ),
          const Divider(),
          InfoRow(
            label: '本地 vault',
            value: profile?.vaultDir ?? '—',
            mono: true,
            selectable: true,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onBackup,
                icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                label: const Text('备份'),
              ),
              OutlinedButton.icon(
                onPressed: onRestore,
                icon: const Icon(Icons.restore_rounded, size: 16),
                label: const Text('恢复'),
              ),
              OutlinedButton.icon(
                onPressed: onVerify,
                icon: const Icon(Icons.verified_outlined, size: 16),
                label: const Text('校验'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
