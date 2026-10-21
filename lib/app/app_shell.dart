import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bootstrap.dart';
import 'pages/about_page.dart';
import 'pages/overview_page.dart';
import 'pages/self_check_page.dart';
import 'self_check_controller.dart';
import 'theme.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (kDebugMode &&
        Platform.environment['EIMMORTAL_AUTORUN_SELFTEST'] == '1') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _index = 1);
        ref.read(selfCheckProvider.notifier).run();
      });
    }
  }

  void _startSelfCheck() {
    setState(() => _index = 1);
    ref.read(selfCheckProvider.notifier).run();
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(bootstrapProvider);
    final info = bootstrap.value;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 880;
          return Row(
            children: [
              _Sidebar(
                compact: compact,
                index: _index,
                info: info,
                loading: bootstrap.isLoading,
                onSelect: (value) => setState(() => _index = value),
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(1.05, -1.1),
                      radius: 1.2,
                      colors: [Color(0x142B8F6B), Colors.transparent],
                    ),
                  ),
                  child: IndexedStack(
                    index: _index,
                    children: [
                      OverviewPage(
                        onOpenSelfCheck: () => setState(() => _index = 1),
                        onRunSelfCheck: _startSelfCheck,
                      ),
                      const SelfCheckPage(),
                      const AboutPage(),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.compact,
    required this.index,
    required this.info,
    required this.loading,
    required this.onSelect,
  });

  final bool compact;
  final int index;
  final BootstrapInfo? info;
  final bool loading;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final statusColor = loading
        ? AppColors.amber
        : info?.ready == true
        ? AppColors.accent
        : AppColors.danger;
    final statusLabel = loading
        ? '正在连接核心'
        : info?.ready == true
        ? '核心就绪'
        : '核心不可用';

    return Container(
      width: compact ? 76 : 232,
      decoration: const BoxDecoration(
        color: Color(0xFF080D18),
        border: Border(right: BorderSide(color: AppColors.borderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 18 : 20,
              compact ? 24 : 26,
              compact ? 18 : 20,
              20,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.accent, AppColors.accentDeep],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shield_moon_outlined,
                    color: Color(0xFF04140D),
                    size: 20,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Encry Immortals',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: AppColors.text,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'eimmortal desktop',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.faint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(),
          const SizedBox(height: 14),
          _NavItem(
            compact: compact,
            icon: Icons.space_dashboard_outlined,
            selectedIcon: Icons.space_dashboard_rounded,
            label: '概览',
            selected: index == 0,
            onTap: () => onSelect(0),
          ),
          _NavItem(
            compact: compact,
            icon: Icons.science_outlined,
            selectedIcon: Icons.science_rounded,
            label: '自检',
            selected: index == 1,
            onTap: () => onSelect(1),
            badge: 'M0',
          ),
          _NavItem(
            compact: compact,
            icon: Icons.info_outline_rounded,
            selectedIcon: Icons.info_rounded,
            label: '关于',
            selected: index == 2,
            onTap: () => onSelect(2),
          ),
          const Spacer(),
          Padding(
            padding: EdgeInsets.all(compact ? 14 : 18),
            child: compact
                ? Tooltip(
                    message: '$statusLabel · ${info?.version ?? '—'}',
                    child: Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderSoft),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: statusColor.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                statusLabel,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                info?.version == null
                                    ? 'M0 · 开发构建'
                                    : 'core ${info!.version}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.faint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.compact,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final bool compact;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final content = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.surface,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 42,
          margin: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: 2,
          ),
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.09)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.22)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(
                selected ? selectedIcon : icon,
                size: 18,
                color: selected ? AppColors.accent : AppColors.muted,
              ),
              if (!compact) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? AppColors.text : AppColors.muted,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.blue,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    if (compact) return Tooltip(message: label, child: content);
    return content;
  }
}
