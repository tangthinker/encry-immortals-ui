import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../app_controller.dart';
import '../app_info.dart';
import '../theme.dart';
import '../window_title.dart';
import 'backup_page.dart';
import 'dashboard_page.dart';
import 'history_page.dart';
import 'restore_page.dart';
import 'settings_page.dart';
import 'verify_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({required this.controller, super.key});

  final AppController controller;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final Set<int> _visited = {0};
  static const _sectionTitles = ['概览', '备份', '历史', '恢复', '校验', '设置'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setAppWindowTitle(_sectionTitles[_index]);
    });
  }

  void _navigate(int index) {
    setState(() {
      _index = index;
      _visited.add(index);
    });
    setAppWindowTitle(_sectionTitles[index]);
  }

  Future<void> _quitApp() async {
    final busy = widget.controller.queue.isBusy;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(busy ? '命令仍在运行，退出？' : '退出 $appName？'),
        content: Text(
          busy
              ? '退出会取消当前命令。写入被中断时可能留下 TargetDir 写锁。'
              : '退出后主密码会从内存清除，下次需要重新输入。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(busy ? '取消命令并退出' : '退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (busy) await widget.controller.queue.cancelCurrent();
    await widget.controller.quit(force: true);
  }

  void _invokeTextIntent(Intent intent) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return;
    Actions.maybeInvoke(focusContext, intent);
  }

  List<PlatformMenuItem> _buildMenus(bool busy) {
    final controller = widget.controller;
    final nav = <PlatformMenuItem>[
      for (var index = 0; index < 5; index++)
        PlatformMenuItem(
          label: _sectionTitles[index],
          shortcut: SingleActivator(
            LogicalKeyboardKey(0x00000000030 + index + 1),
            meta: true,
          ),
          onSelected: () => _navigate(index),
        ),
    ];
    return <PlatformMenuItem>[
      PlatformMenu(
        label: appName,
        menus: <PlatformMenuItem>[
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.about,
          ),
          PlatformMenuItem(
            label: '设置…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.comma,
              meta: true,
            ),
            onSelected: () => _navigate(5),
          ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.servicesSubmenu,
          ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.hide,
          ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.hideOtherApplications,
          ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.showAllApplications,
          ),
          PlatformMenuItem(
            label: '退出 $appName',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyQ,
              meta: true,
            ),
            onSelected: () => _quitApp(),
          ),
        ],
      ),
      PlatformMenu(
        label: '文件',
        menus: <PlatformMenuItem>[
          PlatformMenuItem(
            label: '备份…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyB,
              meta: true,
              shift: true,
            ),
            onSelected: () => _navigate(1),
          ),
          PlatformMenuItem(
            label: '恢复…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyR,
              meta: true,
              shift: true,
            ),
            onSelected: () => _navigate(3),
          ),
          PlatformMenuItem(
            label: '校验…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyY,
              meta: true,
            ),
            onSelected: () => _navigate(4),
          ),
          PlatformMenuItem(
            label: '关闭窗口',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyW,
              meta: true,
            ),
            onSelected: () => closeAppWindow(),
          ),
        ],
      ),
      PlatformMenu(
        label: '编辑',
        menus: <PlatformMenuItem>[
          PlatformMenuItem(
            label: '撤销',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyZ,
              meta: true,
            ),
            onSelected: () => _invokeTextIntent(
              const UndoTextIntent(SelectionChangedCause.keyboard),
            ),
          ),
          PlatformMenuItem(
            label: '重做',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyZ,
              meta: true,
              shift: true,
            ),
            onSelected: () => _invokeTextIntent(
              const RedoTextIntent(SelectionChangedCause.keyboard),
            ),
          ),
          PlatformMenuItem(
            label: '剪切',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyX,
              meta: true,
            ),
            onSelected: () => _invokeTextIntent(
              CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
            ),
          ),
          PlatformMenuItem(
            label: '拷贝',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyC,
              meta: true,
            ),
            onSelected: () =>
                _invokeTextIntent(CopySelectionTextIntent.copy),
          ),
          PlatformMenuItem(
            label: '粘贴',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyV,
              meta: true,
            ),
            onSelected: () => _invokeTextIntent(
              const PasteTextIntent(SelectionChangedCause.keyboard),
            ),
          ),
          PlatformMenuItem(
            label: '全选',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyA,
              meta: true,
            ),
            onSelected: () => _invokeTextIntent(
              const SelectAllTextIntent(SelectionChangedCause.keyboard),
            ),
          ),
        ],
      ),
      PlatformMenu(
        label: '显示',
        menus: <PlatformMenuItem>[
          ...nav,
          PlatformMenuItem(
            label: '刷新',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyR,
              meta: true,
            ),
            onSelected: controller.requestRefresh,
          ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.toggleFullScreen,
          ),
        ],
      ),
      PlatformMenu(
        label: '操作',
        menus: <PlatformMenuItem>[
          PlatformMenuItem(
            label: '锁定',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyL,
              meta: true,
            ),
            onSelected: busy ? null : () => _lock(),
          ),
        ],
      ),
      PlatformMenu(
        label: '窗口',
        menus: const <PlatformMenuItem>[
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.minimizeWindow,
          ),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.zoomWindow,
          ),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
          ),
        ],
      ),
      PlatformMenu(
        label: '帮助',
        menus: <PlatformMenuItem>[
          PlatformMenuItem(
            label: '打开项目文档',
            onSelected: () => controller.platform.openUrl(
              'https://github.com/tangthinker/encry-immortals',
            ),
          ),
          PlatformMenuItem(
            label: '报告问题',
            onSelected: () => controller.platform.openUrl(
              'https://github.com/tangthinker/encry-immortals/issues',
            ),
          ),
        ],
      ),
    ];
  }

  Widget _pageAt(int index) {
    if (!_visited.contains(index)) return const SizedBox.shrink();
    return switch (index) {
      0 => DashboardPage(controller: widget.controller, onNavigate: _navigate),
      1 => BackupPage(controller: widget.controller),
      2 => HistoryPage(controller: widget.controller),
      3 => RestorePage(controller: widget.controller),
      4 => VerifyPage(controller: widget.controller),
      _ => SettingsPage(
        controller: widget.controller,
        onDone: () => _navigate(0),
      ),
    };
  }

  Future<void> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('取消正在运行的操作？'),
        content: const Text(
          '会向 sidecar 发送终止信号。写入被中断时可能留下 TargetDir 写锁；'
          '下次备份应使用“--break-lock 重试”或先检查锁。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续等待'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('取消操作'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.queue.cancelCurrent();
    }
  }

  void _lock() {
    if (!widget.controller.lock()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('命令运行中，结束后才能锁定。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller.queue,
      builder: (context, _) {
        final busy = controller.queue.isBusy;
        final scaffold = Scaffold(
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Sidebar(
                  controller: controller,
                  index: _index,
                  busy: busy,
                  onSelect: _navigate,
                  onLock: _lock,
                  onSettings: () => _navigate(5),
                ),
                Expanded(
                  child: Column(
                    children: [
                      if (busy)
                        _BusyBar(
                          label: controller.queue.currentLabel ?? '正在运行',
                          onCancel: _confirmCancel,
                        ),
                      if (controller.targetLock?.locked == true && !busy)
                        _TargetLockBanner(onDiagnose: () => _navigate(5)),
                      Expanded(
                        child: IndexedStack(
                          index: _index,
                          children: [
                            for (var page = 0; page < 6; page++) _pageAt(page),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
        Widget content = scaffold;
        if (Platform.isMacOS) {
          content = PlatformMenuBar(
            menus: _buildMenus(busy),
            child: content,
          );
        } else {
          content = CallbackShortcuts(
            bindings: {
              for (var index = 0; index < 5; index++)
                SingleActivator(
                  LogicalKeyboardKey(0x00000000030 + index + 1),
                  control: true,
                ): () => _navigate(index),
              const SingleActivator(
                LogicalKeyboardKey.keyB,
                control: true,
                shift: true,
              ): () => _navigate(1),
              const SingleActivator(
                LogicalKeyboardKey.keyR,
                control: true,
                shift: true,
              ): () => _navigate(3),
              const SingleActivator(
                LogicalKeyboardKey.keyY,
                control: true,
              ): () => _navigate(4),
              const SingleActivator(
                LogicalKeyboardKey.keyR,
                control: true,
              ): controller.requestRefresh,
              const SingleActivator(
                LogicalKeyboardKey.keyL,
                control: true,
              ): () {
                if (!busy) _lock();
              },
              const SingleActivator(
                LogicalKeyboardKey.comma,
                control: true,
              ): () => _navigate(5),
            },
            child: content,
          );
        }
        return content;
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.controller,
    required this.index,
    required this.busy,
    required this.onSelect,
    required this.onLock,
    required this.onSettings,
  });

  final AppController controller;
  final int index;
  final bool busy;
  final ValueChanged<int> onSelect;
  final VoidCallback onLock;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final profile = controller.profile;
    final targetName = profile == null ? '未配置' : p.basename(profile.targetDir);
    return Container(
      width: 240,
      decoration:  BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.borderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child:  Icon(
                    Icons.shield_moon_outlined,
                    size: 19,
                    color: AppColors.onAccent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        targetName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.faint,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '更多',
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    size: 18,
                    color: AppColors.muted,
                  ),
                  color: AppColors.surfaceRaised,
                  onSelected: (value) {
                    if (value == 'lock' && !busy) onLock();
                    if (value == 'settings') onSettings();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'lock',
                      enabled: !busy,
                      child: const Text('锁定'),
                    ),
                    const PopupMenuItem(
                      value: 'settings',
                      child: Text('设置…'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          const SizedBox(height: 10),
          _NavItem(
            selected: index == 0,
            icon: Icons.space_dashboard_outlined,
            selectedIcon: Icons.space_dashboard_rounded,
            label: '概览',
            onTap: () => onSelect(0),
          ),
          _NavItem(
            selected: index == 1,
            icon: Icons.cloud_upload_outlined,
            selectedIcon: Icons.cloud_upload_rounded,
            label: '备份',
            onTap: () => onSelect(1),
          ),
          _NavItem(
            selected: index == 2,
            icon: Icons.history_rounded,
            selectedIcon: Icons.history_rounded,
            label: '历史',
            onTap: () => onSelect(2),
          ),
          _NavItem(
            selected: index == 3,
            icon: Icons.restore_rounded,
            selectedIcon: Icons.restore_rounded,
            label: '恢复',
            onTap: () => onSelect(3),
          ),
          _NavItem(
            selected: index == 4,
            icon: Icons.verified_outlined,
            selectedIcon: Icons.verified_rounded,
            label: '校验',
            onTap: () => onSelect(4),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppColors.borderSoft),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration:  BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'core ${controller.coreVersion ?? '—'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:  TextStyle(
                            fontFamily: 'Menlo',
                            fontSize: 10,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                 Center(
                  child: Text(
                    'v$appVersion',
                    style: TextStyle(fontSize: 10, color: AppColors.faint),
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.surfaceRaised,
        child: Container(
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent.withValues(alpha: 0.09) : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.2)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? selectedIcon : icon,
                size: 17,
                color: selected ? AppColors.accent : AppColors.muted,
              ),
              const SizedBox(width: 11),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? AppColors.text : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetLockBanner extends StatelessWidget {
  const _TargetLockBanner({required this.onDiagnose});

  final VoidCallback onDiagnose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration:  BoxDecoration(
        color: AppColors.warningSurface,
        border: Border(bottom: BorderSide(color: AppColors.warningBorder)),
      ),
      child: Row(
        children: [
           Icon(Icons.warning_amber_rounded, size: 15, color: AppColors.amber),
          const SizedBox(width: 8),
           Expanded(
            child: Text(
              '检测到 TargetDir 写锁：上次写入可能被中断。确认没有其他进程后，在设置中诊断。',
              style: TextStyle(fontSize: 11.5, color: AppColors.amber),
            ),
          ),
          TextButton(onPressed: onDiagnose, child: const Text('诊断')),
        ],
      ),
    );
  }
}

class _BusyBar extends StatelessWidget {
  const _BusyBar({required this.label, required this.onCancel});

  final String label;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration:  BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border(bottom: BorderSide(color: AppColors.borderSoft)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$label · 所有命令严格串行',
              style:  TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ),
          TextButton(
            onPressed: onCancel,
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}
