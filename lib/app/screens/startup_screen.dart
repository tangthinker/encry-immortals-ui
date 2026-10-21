import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../theme.dart';
import '../widgets/app_mark.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppMark(size: 54),
            SizedBox(height: 20),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 14),
            Text(
              '正在启动 Encry Immortals…',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class StartupFailureScreen extends StatefulWidget {
  const StartupFailureScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<StartupFailureScreen> createState() => _StartupFailureScreenState();
}

class _StartupFailureScreenState extends State<StartupFailureScreen> {
  bool _busy = false;
  String? _actionError;

  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await widget.controller.retryStartup();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('重置本地配置？'),
        content: const Text(
          '会删除应用数据目录里的 profile、config.toml 和本地控制平面（vault）。'
          'TargetDir 与其他备份数据不会被动。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await widget.controller.resetLocalConfig();
    } catch (error) {
      if (mounted) setState(() => _actionError = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final error = controller.startupError ?? '启动失败。';
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const AppMark(size: 44),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          '无法启动',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => controller.quit(),
                        child: const Text('退出'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    error,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: AppColors.muted,
                    ),
                  ),
                  if (kDebugMode &&
                      (error.contains('sidecar') || error.contains('核心'))) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderSoft),
                      ),
                      child: const SelectableText(
                        '开发模式可用 EIMMORTAL_CORE_PATH 指向本地 sidecar：\n'
                        'EIMMORTAL_CORE_PATH=/path/to/eimmortal flutter run -d macos',
                        style: TextStyle(
                          fontFamily: 'Menlo',
                          fontSize: 11.5,
                          height: 1.6,
                          color: AppColors.faint,
                        ),
                      ),
                    ),
                  ],
                  if (_actionError != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _actionError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _retry,
                        icon: _busy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF04140D),
                                ),
                              )
                            : const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('重试'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            controller.platform.revealPath(controller.paths.root),
                        icon: const Icon(Icons.folder_open_rounded, size: 17),
                        label: const Text('打开应用数据目录'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _reset,
                        child: const Text(
                          '重置本地配置',
                          style: TextStyle(color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SelectableText(
                    'host: ${Platform.operatingSystem} · app data: ${controller.paths.root}',
                    style: const TextStyle(
                      fontFamily: 'Menlo',
                      fontSize: 10.5,
                      color: AppColors.faint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
