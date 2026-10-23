import 'dart:io';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../window_title.dart';
import '../../core/profile.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/app_mark.dart';
import '../widgets/section_card.dart';
import '../widgets/workspace_switcher.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final TextEditingController _password = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setAppWindowTitle('解锁');
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _password
      ..text = ''
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_submitting || widget.controller.unlocking) return;
    final password = _password.text;
    if (password.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final outcome = await widget.controller.unlock(password);
      if (outcome.success) {
        _password.clear();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('重置当前工作区？'),
        content: const Text(
          '会删除当前工作区的控制平面与 profile，其他工作区和 TargetDir 不会被动。'
          '重新加入需要 Armor Key 与主密码。',
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
    try {
      await widget.controller.resetLocalConfig();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final profile = controller.profile;
    final busy = _submitting || controller.unlocking;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 840;
                final info = _LibraryInfo(
                  controller: controller,
                  profile: profile,
                );
                final form = _UnlockForm(
                  controller: controller,
                  password: _password,
                  focus: _focus,
                  obscure: _obscure,
                  busy: busy,
                  onToggleObscure: () => setState(() => _obscure = !_obscure),
                  onSubmit: _unlock,
                  onReset: _reset,
                );
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 11, child: info),
                      const SizedBox(width: 20),
                      Expanded(flex: 9, child: form),
                    ],
                  );
                }
                return Column(
                  children: [info, const SizedBox(height: 20), form],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryInfo extends StatelessWidget {
  const _LibraryInfo({required this.controller, required this.profile});

  final AppController controller;
  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    final status = controller.previewStatus;
    final targetDir = profile?.targetDir ?? '—';
    final sourceRoot = profile?.sourceRoot ?? '—';
    final targetExists = targetDir != '—' && Directory(targetDir).existsSync();
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppMark(size: 42),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Encry Immortals',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '本地加密备份控制台',
                      style: TextStyle(fontSize: 11, color: AppColors.faint),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: targetExists ? '目标可访问' : '目标不可访问',
                color: targetExists ? AppColors.success : AppColors.amber,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            profile?.name ?? '备份库',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            profile?.mode.label ?? '本地备份库',
            style: TextStyle(fontSize: 12.5, color: AppColors.faint),
          ),
          const SizedBox(height: 24),
          const Divider(),
          InfoRow(
            label: 'TargetDir',
            value: targetDir,
            mono: true,
            selectable: true,
          ),
          const Divider(),
          InfoRow(
            label: '源根目录',
            value: sourceRoot,
            mono: true,
            selectable: true,
          ),
          const Divider(),
          const SizedBox(height: 16),
          Row(
            children: [
              _Metric(
                label: '最近提交',
                value: status == null ? '—' : 'seq ${status.lastSeq}',
              ),
              const SizedBox(width: 10),
              _Metric(
                label: '本地 pack',
                value: status == null ? '—' : '${status.localPacks}',
              ),
              const SizedBox(width: 10),
              _Metric(
                label: '密文体积',
                value: status == null
                    ? '—'
                    : formatBytes(status.packTotalBytes),
              ),
            ],
          ),
          if (controller.targetLock?.locked == true) ...[
            const SizedBox(height: 18),
            NoticeBanner(
              title: '检测到写锁',
              message:
                  'TargetDir 中存在 .eimmortal.lock，上次写入可能被中断。'
                  '进入应用后可在设置中诊断，不要直接删除。',
              color: AppColors.amber,
              icon: Icons.lock_outline_rounded,
            ),
          ],
          if (status != null && status.warnings.isNotEmpty) ...[
            const SizedBox(height: 18),
            NoticeBanner(
              title: '健康提醒',
              message: status.warnings.join('\n'),
              color: AppColors.amber,
            ),
          ],
          const SizedBox(height: 24),
          Text(
            '主密码只存在于当前进程内存，不会写入磁盘或日志。锁定或退出后需要重新输入。',
            style: TextStyle(fontSize: 11, height: 1.6, color: AppColors.faint),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.borderSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10.5, color: AppColors.faint),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnlockForm extends StatelessWidget {
  const _UnlockForm({
    required this.controller,
    required this.password,
    required this.focus,
    required this.obscure,
    required this.busy,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.onReset,
  });

  final AppController controller;
  final TextEditingController password;
  final FocusNode focus;
  final bool obscure;
  final bool busy;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final error = controller.unlockError;
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '解锁',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '使用主密码解锁控制平面，密码不会保存。',
            style: TextStyle(fontSize: 12.5, color: AppColors.faint),
          ),
          const SizedBox(height: 26),
          TextField(
            controller: password,
            focusNode: focus,
            obscureText: obscure,
            autofocus: true,
            enabled: !busy,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              labelText: '主密码',
              hintText: '输入创建库时设置的主密码',
              suffixIcon: IconButton(
                onPressed: onToggleObscure,
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: AppColors.faint,
                ),
                tooltip: obscure ? '显示密码' : '隐藏密码',
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            NoticeBanner(
              title: '解锁失败',
              message: error,
              color: AppColors.danger,
              icon: Icons.lock_outline_rounded,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : onSubmit,
            child: busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onAccent,
                    ),
                  )
                : const Text('解锁'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () => showWorkspaceSwitcher(context, controller),
                icon: const Icon(Icons.swap_horiz_rounded, size: 15),
                label: const Text('切换工作区'),
              ),
              const Spacer(),
              TextButton(
                onPressed: busy ? null : onReset,
                child: Text(
                  '忘记密码或重置当前工作区',
                  style: TextStyle(color: AppColors.faint, fontSize: 12),
                ),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: AppColors.faint,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '连续失败不会删除数据；请确认是否还有 CLI 或其他实例在运行。',
                  style: TextStyle(fontSize: 10.5, color: AppColors.faint),
                ),
              ),
              TextButton(
                onPressed: () => controller.quit(),
                child: const Text('退出'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
