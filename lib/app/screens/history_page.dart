import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../../core/core_models.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/page_header.dart';
import '../widgets/section_card.dart';
import '../widgets/snapshot_tree.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({required this.controller, super.key});

  final AppController controller;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<CommitEntry> _commits = [];
  bool _loading = true;
  String? _error;
  int? _selectedSeq;
  CommitDetail? _detail;
  bool _detailLoading = false;
  String? _detailError;
  int _tab = 0;
  List<FileEntry>? _entries;
  bool _treeLoading = false;
  String? _treeError;
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
      _loading = _commits.isEmpty;
      _error = null;
    });
    try {
      final result = await session.history();
      if (!mounted) return;
      if (!result.isSuccess || result.jsonList == null) {
        setState(() {
          _loading = false;
          _error =
              '${result.exit.label}（exit ${result.exitCode}）\n'
              '${result.exit.guidance}\n${result.errorSummary}';
        });
        return;
      }
      final commits = result.jsonList!
          .map((item) => CommitEntry.fromJson(asJsonMap(item)))
          .toList()
        ..sort((a, b) => b.seq.compareTo(a.seq));
      setState(() {
        _commits = commits;
        _loading = false;
        _error = null;
      });
      if (commits.isEmpty) {
        setState(() {
          _selectedSeq = null;
          _detail = null;
          _entries = null;
        });
        return;
      }
      final target = previous != null &&
              commits.any((commit) => commit.seq == previous)
          ? previous
          : commits.first.seq;
      if (_selectedSeq != target || _detail == null) {
        await _select(target);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _select(int seq) async {
    final session = widget.controller.session;
    if (session == null) return;
    setState(() {
      _selectedSeq = seq;
      _detail = null;
      _detailError = null;
      _detailLoading = true;
      _entries = null;
      _treeError = null;
    });
    final result = await session.show(seq);
    if (!mounted || _selectedSeq != seq) return;
    if (!result.isSuccess || result.jsonMap == null) {
      setState(() {
        _detailLoading = false;
        _detailError =
            '${result.exit.label}（exit ${result.exitCode}）\n${result.errorSummary}';
      });
      return;
    }
    setState(() {
      _detail = CommitDetail.fromJson(result.jsonMap!);
      _detailLoading = false;
      _detailError = null;
    });
    if (_tab == 1) await _loadTree();
  }

  Future<void> _loadTree() async {
    final seq = _selectedSeq;
    final session = widget.controller.session;
    if (seq == null || session == null) return;
    setState(() {
      _treeLoading = true;
      _treeError = null;
    });
    final result = await session.listSnapshot(seq);
    if (!mounted || _selectedSeq != seq) return;
    if (!result.isSuccess || result.jsonList == null) {
      setState(() {
        _treeLoading = false;
        _treeError =
            '${result.exit.label}（exit ${result.exitCode}）\n${result.errorSummary}';
      });
      return;
    }
    setState(() {
      _entries = result.jsonList!
          .map((item) => FileEntry.fromJson(asJsonMap(item)))
          .toList();
      _treeLoading = false;
      _treeError = null;
    });
  }

  void _switchTab(int tab) {
    setState(() => _tab = tab);
    if (tab == 1 && _entries == null && !_treeLoading) {
      _loadTree();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: '历史',
            subtitle: '提交列表来自 log；详情来自 show；文件树来自 ls --at',
            trailing: TextButton.icon(
              onPressed: _loading ? null : () => _loadHistory(),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('刷新'),
            ),
          ),
          const SizedBox(height: 20),
          if (_error != null) ...[
            NoticeBanner(
              title: '读取历史失败',
              message: _error!,
              color: AppColors.danger,
              icon: Icons.error_outline_rounded,
            ),
            const SizedBox(height: 14),
          ],
          Expanded(
            child: _loading && _commits.isEmpty
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _commits.isEmpty
                ? SectionCard(
                    child: EmptyState(
                      icon: Icons.history_rounded,
                      title: '还没有提交',
                      message: '去“备份”页完成第一次备份后，这里会显示提交历史与文件快照。',
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 320,
                        child: _CommitList(
                          commits: _commits,
                          selectedSeq: _selectedSeq,
                          onSelect: _select,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _DetailPanel(
                          detail: _detail,
                          loading: _detailLoading,
                          error: _detailError,
                          tab: _tab,
                          onTab: _switchTab,
                          entries: _entries,
                          treeLoading: _treeLoading,
                          treeError: _treeError,
                          onLoadTree: _loadTree,
                          onRetryDetail: _selectedSeq == null
                              ? null
                              : () => _select(_selectedSeq!),
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

class _CommitList extends StatelessWidget {
  const _CommitList({
    required this.commits,
    required this.selectedSeq,
    required this.onSelect,
  });

  final List<CommitEntry> commits;
  final int? selectedSeq;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                const Text(
                  '提交',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const Spacer(),
                Text(
                  '${commits.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.faint,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: commits.length,
              itemBuilder: (context, index) {
                final commit = commits[index];
                final selected = commit.seq == selectedSeq;
                return Material(
                  color: selected
                      ? AppColors.accent.withValues(alpha: 0.07)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => onSelect(commit.seq),
                    hoverColor: AppColors.surfaceRaised,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            width: 2,
                            color: selected
                                ? AppColors.accent
                                : Colors.transparent,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'seq ${commit.seq}',
                                style: TextStyle(
                                  fontFamily: 'Menlo',
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? AppColors.accent
                                      : AppColors.text,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                formatDateTime(commit.timestamp),
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  color: AppColors.faint,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            commit.message.isEmpty ? '（无提交信息）' : commit.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${commit.ops} ops · ${commit.packs} packs',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.faint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.detail,
    required this.loading,
    required this.error,
    required this.tab,
    required this.onTab,
    required this.entries,
    required this.treeLoading,
    required this.treeError,
    required this.onLoadTree,
    required this.onRetryDetail,
  });

  final CommitDetail? detail;
  final bool loading;
  final String? error;
  final int tab;
  final ValueChanged<int> onTab;
  final List<FileEntry>? entries;
  final bool treeLoading;
  final String? treeError;
  final VoidCallback onLoadTree;
  final VoidCallback? onRetryDetail;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (detail == null) ...[
            Expanded(
              child: loading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : EmptyState(
                      icon: Icons.article_outlined,
                      title: error == null ? '选择一个提交' : '读取详情失败',
                      message: error ?? '左侧列表中的每个 seq 对应一次提交。',
                      action: onRetryDetail == null
                          ? null
                          : OutlinedButton(
                              onPressed: onRetryDetail,
                              child: const Text('重试'),
                            ),
                    ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'seq ${detail!.seq}',
                        style: const TextStyle(
                          fontFamily: 'Menlo',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(width: 10),
                      StatusPill(
                        label: detail!.kind,
                        color: AppColors.blue,
                        dense: true,
                      ),
                      const Spacer(),
                      Text(
                        formatDateTime(detail!.timestamp),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.faint,
                        ),
                      ),
                    ],
                  ),
                  if (detail!.message.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      detail!.message,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.55,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      KeyValueChip(label: 'ops', value: '${detail!.ops.length}'),
                      KeyValueChip(label: 'dirs', value: '${detail!.dirs}'),
                      KeyValueChip(label: 'packs', value: '${detail!.packs}'),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  _TabButton(
                    label: '变更 (${detail!.ops.length})',
                    selected: tab == 0,
                    onTap: () => onTab(0),
                  ),
                  const SizedBox(width: 6),
                  _TabButton(
                    label: '文件树',
                    selected: tab == 1,
                    onTap: () => onTab(1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: tab == 0
                  ? _OpsList(ops: detail!.ops)
                  : _TreeContent(
                      entries: entries,
                      loading: treeLoading,
                      error: treeError,
                      onRetry: onLoadTree,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? AppColors.border : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.text : AppColors.faint,
          ),
        ),
      ),
    );
  }
}

class _OpsList extends StatelessWidget {
  const _OpsList({required this.ops});

  final List<CommitOp> ops;

  @override
  Widget build(BuildContext context) {
    if (ops.isEmpty) {
      return const Center(
        child: Text(
          '这次提交没有文件变更（可能是 note）',
          style: TextStyle(fontSize: 12, color: AppColors.faint),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: ops.length,
      itemBuilder: (context, index) {
        final op = ops[index];
        final color = _color(op);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon(op), size: 14, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  op.path,
                  style: const TextStyle(
                    fontFamily: 'Menlo',
                    fontSize: 11.5,
                    height: 1.5,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (op.extra != null)
                Text(
                  '→ ${op.extra}',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.faint),
                ),
              if (!op.isDir) ...[
                const SizedBox(width: 10),
                Text(
                  formatBytes(op.size),
                  style: const TextStyle(
                    fontFamily: 'Menlo',
                    fontSize: 10.5,
                    color: AppColors.faint,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Text(
                _label(op),
                style: TextStyle(fontSize: 10, color: color),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _icon(CommitOp op) => switch (op.type) {
    'add' => Icons.add_circle_outline_rounded,
    'delete' => Icons.remove_circle_outline_rounded,
    'mkdir' => Icons.create_new_folder_outlined,
    'rmdir' => Icons.folder_delete_outlined,
    'link' => Icons.link_rounded,
    _ => Icons.edit_outlined,
  };

  Color _color(CommitOp op) => switch (op.type) {
    'add' => AppColors.accent,
    'delete' => AppColors.danger,
    'rmdir' => AppColors.danger,
    'mkdir' => AppColors.amber,
    _ => AppColors.blue,
  };

  String _label(CommitOp op) => switch (op.type) {
    'add' => '新增',
    'delete' => '删除',
    'mkdir' => '目录',
    'rmdir' => '删目录',
    'link' => '链接',
    _ => '修改',
  };
}

class _TreeContent extends StatelessWidget {
  const _TreeContent({
    required this.entries,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final List<FileEntry>? entries;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (error != null) {
      return EmptyState(
        icon: Icons.folder_off_outlined,
        title: '读取文件树失败',
        message: error!,
        action: OutlinedButton(onPressed: onRetry, child: const Text('重试')),
      );
    }
    if (entries == null) {
      return const Center(
        child: Text('文件树未加载', style: TextStyle(fontSize: 12, color: AppColors.faint)),
      );
    }
    if (entries!.isEmpty) {
      return const Center(
        child: Text('快照为空', style: TextStyle(fontSize: 12, color: AppColors.faint)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: SnapshotTree(entries: entries!),
    );
  }
}
