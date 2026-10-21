import 'package:flutter/material.dart';

import '../../core/core_models.dart';
import '../format.dart';
import '../theme.dart';

class SnapshotTree extends StatefulWidget {
  const SnapshotTree({required this.entries, super.key});

  final List<FileEntry> entries;

  @override
  State<SnapshotTree> createState() => _SnapshotTreeState();
}

class _SnapshotTreeState extends State<SnapshotTree> {
  final TextEditingController _search = TextEditingController();
  final Set<String> _expanded = {'/'};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      setState(() => _query = _search.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final root = _TreeNode(path: '/', name: '/', isDir: true);
    for (final entry in widget.entries) {
      _insert(root, entry);
    }
    _sort(root);

    final rows = _query.isEmpty
        ? _flatten(root)
        : _searchRows(root);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            hintText: '按路径过滤…',
            prefixIcon: Icon(Icons.search_rounded, size: 17),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '${widget.entries.length} 个条目',
              style: const TextStyle(fontSize: 10.5, color: AppColors.faint),
            ),
            if (widget.entries.length > 5000) ...[
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '快照较大，已一次加载；建议用路径过滤缩小范围。',
                  style: TextStyle(fontSize: 10.5, color: AppColors.amber),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text(
                    '没有匹配的文件',
                    style: TextStyle(fontSize: 12, color: AppColors.faint),
                  ),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return _TreeRow(
                      node: row.node,
                      depth: row.depth,
                      expanded: _expanded.contains(row.node.path),
                      highlight: _query.isNotEmpty,
                      onTap: row.node.isDir
                          ? () {
                              setState(() {
                                if (_expanded.contains(row.node.path)) {
                                  _expanded.remove(row.node.path);
                                } else {
                                  _expanded.add(row.node.path);
                                }
                              });
                            }
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _insert(_TreeNode root, FileEntry entry) {
    final parts = entry.path.split('/').where((part) => part.isNotEmpty);
    var current = root;
    for (final part in parts) {
      current = current.children.putIfAbsent(
        part,
        () => _TreeNode(
          path: current.path == '/' ? part : '${current.path}/$part',
          name: part,
          isDir: true,
        ),
      );
    }
    current.isDir = entry.isDir;
    current.size = entry.size;
    current.target = entry.target;
  }

  void _sort(_TreeNode node) {
    final children = node.children.values.toList()
      ..sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    node.sortedChildren = children;
    for (final child in children) {
      _sort(child);
    }
  }

  List<_FlatRow> _flatten(_TreeNode root) {
    final rows = <_FlatRow>[];
    void visit(_TreeNode node, int depth) {
      for (final child in node.sortedChildren) {
        rows.add(_FlatRow(node: child, depth: depth));
        if (child.isDir && _expanded.contains(child.path)) {
          visit(child, depth + 1);
        }
      }
    }

    visit(root, 0);
    return rows;
  }

  List<_FlatRow> _searchRows(_TreeNode root) {
    final rows = <_FlatRow>[];
    void visit(_TreeNode node) {
      for (final child in node.sortedChildren) {
        if (child.path.toLowerCase().contains(_query)) {
          rows.add(_FlatRow(node: child, depth: child.path.split('/').length - 1));
        }
        visit(child);
      }
    }

    visit(root);
    rows.sort((a, b) => a.node.path.compareTo(b.node.path));
    return rows;
  }
}

class _TreeNode {
  _TreeNode({
    required this.path,
    required this.name,
    required this.isDir,
  });

  final String path;
  final String name;
  bool isDir;
  int size = 0;
  String? target;
  final Map<String, _TreeNode> children = {};
  List<_TreeNode> sortedChildren = [];
}

class _FlatRow {
  const _FlatRow({required this.node, required this.depth});

  final _TreeNode node;
  final int depth;
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.node,
    required this.depth,
    required this.expanded,
    required this.highlight,
    this.onTap,
  });

  final _TreeNode node;
  final int depth;
  final bool expanded;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.surfaceRaised,
        child: Padding(
          padding: EdgeInsets.only(
            left: 6 + depth * 16,
            right: 8,
            top: 5,
            bottom: 5,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 15,
                child: node.isDir
                    ? Icon(
                        expanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_right_rounded,
                        size: 15,
                        color: AppColors.faint,
                      )
                    : null,
              ),
              Icon(
                node.isDir
                    ? Icons.folder_outlined
                    : node.target != null
                    ? Icons.link_rounded
                    : Icons.insert_drive_file_outlined,
                size: 14,
                color: node.isDir ? AppColors.amber : AppColors.blue,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  highlight ? node.path : node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Menlo',
                    fontSize: 11.5,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (!node.isDir)
                Text(
                  formatBytes(node.size),
                  style: const TextStyle(
                    fontFamily: 'Menlo',
                    fontSize: 10,
                    color: AppColors.faint,
                  ),
                ),
              if (node.target != null) ...[
                const SizedBox(width: 8),
                Text(
                  '→ ${node.target}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppColors.faint),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
