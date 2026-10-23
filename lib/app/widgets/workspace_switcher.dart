import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../theme.dart';
import '../../core/workspace_store.dart';

/// Shared workspace picker used by the sidebar and the unlock screen.
Future<void> showWorkspaceSwitcher(
  BuildContext context,
  AppController controller,
) async {
  final busy = controller.queue.isBusy;
  final result = await showDialog<_WorkspaceChoice>(
    context: context,
    barrierDismissible: !busy,
    builder: (context) => _WorkspaceDialog(controller: controller, busy: busy),
  );
  if (result == null || !context.mounted) return;

  if (result.workspaceId != null) {
    final error = await controller.switchWorkspace(result.workspaceId!);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
    return;
  }

  final mode = result.setupMode;
  if (mode == null) return;
  try {
    await controller.beginWorkspaceSetup(mode);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$error')));
  }
}

class _WorkspaceDialog extends StatelessWidget {
  const _WorkspaceDialog({required this.controller, required this.busy});

  final AppController controller;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final workspaces = controller.workspaces;
    final activeId = controller.activeWorkspace?.id;
    return AlertDialog(
      title: const Text('工作区'),
      content: SizedBox(
        width: 580,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '每个工作区拥有独立的 profile、配置文件和本地控制平面；TargetDir 不会被切换操作修改。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.55,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 14),
            if (workspaces.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  '还没有工作区。请新建或导入一个。',
                  style: TextStyle(fontSize: 12, color: AppColors.faint),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: workspaces.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: AppColors.borderSoft),
                  itemBuilder: (context, index) {
                    final workspace = workspaces[index];
                    return _WorkspaceTile(
                      workspace: workspace,
                      selected: workspace.id == activeId,
                      enabled: !busy,
                      onTap: () => Navigator.pop(
                        context,
                        _WorkspaceChoice(workspaceId: workspace.id),
                      ),
                    );
                  },
                ),
              ),
            if (busy) ...[
              const SizedBox(height: 12),
              Text(
                '命令运行中，结束后才能切换工作区。',
                style: TextStyle(fontSize: 11, color: AppColors.amber),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => Navigator.pop(
                          context,
                          const _WorkspaceChoice(
                            setupMode: WorkspaceSetupMode.create,
                          ),
                        ),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('新建工作区'),
                ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => Navigator.pop(
                          context,
                          const _WorkspaceChoice(
                            setupMode: WorkspaceSetupMode.import,
                          ),
                        ),
                  icon: const Icon(Icons.file_download_outlined, size: 16),
                  label: const Text('导入已有工作区'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({
    required this.workspace,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final WorkspaceInfo workspace;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      selected: selected,
      selectedTileColor: AppColors.accent.withValues(alpha: 0.07),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(
        selected ? Icons.folder_special_rounded : Icons.folder_outlined,
        size: 20,
        color: selected ? AppColors.accent : AppColors.muted,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              workspace.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: AppColors.text,
              ),
            ),
          ),
          if (selected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '当前',
                style: TextStyle(fontSize: 10, color: AppColors.accent),
              ),
            ),
        ],
      ),
      subtitle: workspace.targetDir == null
          ? null
          : Text(
              workspace.targetDir!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Menlo',
                fontSize: 10,
                color: AppColors.faint,
              ),
            ),
      trailing: selected
          ? const Icon(Icons.check_rounded, size: 17)
          : const Icon(Icons.chevron_right_rounded, size: 17),
      onTap: enabled && !selected ? onTap : null,
    );
  }
}

class _WorkspaceChoice {
  const _WorkspaceChoice({this.workspaceId, this.setupMode});

  final String? workspaceId;
  final WorkspaceSetupMode? setupMode;
}
