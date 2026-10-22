import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../app_controller.dart';
import '../app_info.dart' as info;
import '../../core/app_preferences.dart';
import '../../core/core_locator.dart';
import '../../core/core_models.dart';
import '../../core/lock_inspector.dart';
import '../../core/vault_session.dart';
import '../../core/vault_settings.dart';
import '../theme.dart';
import '../widgets/backup_schedule_card.dart';
import '../widgets/page_header.dart';
import '../widgets/section_card.dart';
import '../widgets/vault_settings_form.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({required this.controller, this.onDone, super.key});

  final AppController controller;
  final VoidCallback? onDone;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late VaultSettings _settings;
  late GlobalKey<VaultSettingsFormState> _settingsKey;
  bool _saving = false;
  bool _savingTheme = false;
  bool _checkingLocks = false;
  String? _saveError;
  String? _themeError;

  @override
  void initState() {
    super.initState();
    _settings = widget.controller.profile?.settings ?? const VaultSettings();
    _settingsKey = GlobalKey<VaultSettingsFormState>();
  }

  Future<void> _saveSettings() async {
    final form = _settingsKey.currentState;
    final settings = form?.read() ?? _settings;
    final error = settings.validate();
    if (error != null) {
      setState(() => _saveError = error);
      form?.validate();
      return;
    }
    final current = widget.controller.profile?.settings;
    final layoutChanged =
        current != null &&
        (current.packMaxMiB != settings.packMaxMiB ||
            current.slicePlainMiB != settings.slicePlainMiB ||
            current.smallFileMiB != settings.smallFileMiB);
    final xattrDisabled = Platform.isMacOS && settings.ignoreXattr == false;
    if (layoutChanged) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('修改存储结构参数？'),
          content: const Text(
            'pack/slice/small_file 只影响后续备份，已有快照仍可读取；'
            '但不同 pack 尺寸会让同步/校验行为发生变化。确认继续？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认修改'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (xattrDisabled && current?.ignoreXattr != false) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('关闭 xattr 忽略？'),
          content: const Text(
            'macOS 上带扩展属性/ACL 的文件可能让备份以 E21 失败。'
            '只有明确需要保留 xattr 时才关闭。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保持开启'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('仍然关闭'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.controller.updateVaultSettings(settings);
      if (!mounted) return;
      setState(() => _settings = settings);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('参数已保存，下次备份/恢复命令生效。')));
    } catch (error) {
      if (mounted) setState(() => _saveError = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setThemeMode(AppThemeMode mode) async {
    if (_savingTheme || widget.controller.themeMode == mode) return;
    setState(() {
      _savingTheme = true;
      _themeError = null;
    });
    try {
      await widget.controller.setThemeMode(mode);
    } catch (error) {
      if (mounted) setState(() => _themeError = '$error');
    } finally {
      if (mounted) setState(() => _savingTheme = false);
    }
  }

  ButtonStyle _themeSegmentStyle() {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? AppColors.accent
            : AppColors.surfaceRaised;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? AppColors.onAccent
            : AppColors.text;
      }),
      overlayColor: WidgetStatePropertyAll(
        AppColors.accent.withValues(alpha: 0.12),
      ),
      side: WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _diagnoseLocks() async {
    final session = widget.controller.session;
    final profile = widget.controller.profile;
    if (session == null || profile == null || _checkingLocks) return;
    setState(() => _checkingLocks = true);
    try {
      final target = await TargetLockInfo.inspect(profile.targetDir);
      final probe = await session.probeControlLock();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _LockDiagnosticsDialog(
          target: target,
          controlLocked: probe.exitCode == 20,
          vaultDir: profile.vaultDir,
        ),
      );
      await widget.controller.refreshTargetLock();
    } finally {
      if (mounted) setState(() => _checkingLocks = false);
    }
  }

  Future<void> _exportKey() async {
    final session = widget.controller.session;
    if (session == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ExportKeyDialog(session: session),
    );
  }

  Future<void> _lock() async {
    if (!widget.controller.lock()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('命令运行中，结束后才能锁定。')));
    }
  }

  Future<void> _forgetProfile() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ForgetProfileDialog(
        targetDir: widget.controller.profile?.targetDir ?? '',
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.forgetProfile();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _quit() async {
    final busy = widget.controller.queue.isBusy;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(busy ? '命令仍在运行，退出？' : '退出应用？'),
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

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制。')));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final profile = controller.profile;
    final runtime = controller.runtime;
    final busy = controller.queue.isBusy;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: '设置',
                subtitle: '配置、密钥与本地数据；不会显示主密码或日志文件',
                trailing: widget.onDone == null
                    ? null
                    : TextButton.icon(
                        onPressed: widget.onDone,
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: const Text('完成'),
                      ),
              ),
              const SizedBox(height: 22),
              SectionCard(
                title: '当前库',
                subtitle: '单 profile；源根目录在创建时固定',
                trailing: StatusPill(
                  label: profile?.mode.label ?? '未配置',
                  color: AppColors.blue,
                  dense: true,
                ),
                child: Column(
                  children: [
                    InfoRow(label: '名称', value: profile?.name ?? '—'),
                    const Divider(),
                    InfoRow(
                      label: '源目录',
                      value: profile?.sourceRoot ?? '—',
                      mono: true,
                      selectable: true,
                      trailing: _CopyButton(
                        value: profile?.sourceRoot,
                        onCopy: _copy,
                      ),
                    ),
                    const Divider(),
                    InfoRow(
                      label: 'TargetDir',
                      value: profile?.targetDir ?? '—',
                      mono: true,
                      selectable: true,
                      trailing: _CopyButton(
                        value: profile?.targetDir,
                        onCopy: _copy,
                      ),
                    ),
                    const Divider(),
                    InfoRow(
                      label: '本地 vault',
                      value: profile?.vaultDir ?? '—',
                      mono: true,
                      selectable: true,
                      trailing: _CopyButton(
                        value: profile?.vaultDir,
                        onCopy: _copy,
                      ),
                    ),
                    const Divider(),
                    InfoRow(
                      label: '配置文件',
                      value: profile?.configPath ?? '—',
                      mono: true,
                      selectable: true,
                      trailing: _CopyButton(
                        value: profile?.configPath,
                        onCopy: _copy,
                      ),
                    ),
                    const Divider(),
                    InfoRow(
                      label: '创建时间',
                      value: profile == null
                          ? '—'
                          : profile.createdAt.toLocal().toString().substring(
                              0,
                              19,
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SectionCard(
                title: '外观',
                subtitle: '默认浅色；切换后立即保存，下次启动继续使用',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<AppThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: AppThemeMode.light,
                          label: Text('浅色'),
                        ),
                        ButtonSegment(
                          value: AppThemeMode.system,
                          label: Text('跟随系统'),
                        ),
                        ButtonSegment(
                          value: AppThemeMode.dark,
                          label: Text('深色'),
                        ),
                      ],
                      selected: {widget.controller.themeMode},
                      showSelectedIcon: false,
                      style: _themeSegmentStyle(),
                      onSelectionChanged: _savingTheme || busy
                          ? null
                          : (values) => _setThemeMode(values.first),
                    ),
                    if (_themeError != null) ...[
                      const SizedBox(height: 12),
                      NoticeBanner(
                        title: '外观未保存',
                        message: _themeError!,
                        color: AppColors.danger,
                        icon: Icons.error_outline_rounded,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      widget.controller.themeMode == AppThemeMode.system
                          ? '当前跟随系统外观；系统切换时立即更新。'
                          : '当前固定${widget.controller.themeMode.label}${widget.controller.themeMode == AppThemeMode.light ? '（默认）' : ''}。',
                      style: TextStyle(fontSize: 10.5, color: AppColors.faint),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              BackupScheduleCard(controller: widget.controller, enabled: !busy),
              const SizedBox(height: 18),
              SectionCard(
                title: '备份参数',
                subtitle: '普通参数与高级参数；保存后写入 config.toml（0600）',
                trailing: FilledButton(
                  onPressed: busy || _saving ? null : _saveSettings,
                  child: Text(_saving ? '保存中…' : '保存参数'),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    VaultSettingsForm(
                      key: _settingsKey,
                      initial: _settings,
                      enabled: !busy && !_saving,
                      onChanged: (value) => _settings = value,
                    ),
                    if (_saveError != null) ...[
                      const SizedBox(height: 12),
                      NoticeBanner(
                        title: '参数未保存',
                        message: _saveError!,
                        color: AppColors.danger,
                        icon: Icons.error_outline_rounded,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: busy || _saving ? null : _saveSettings,
                        icon: const Icon(Icons.save_outlined, size: 16),
                        label: Text(_saving ? '保存中…' : '保存参数'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '修改会立即写入本地配置，并在下一次 sidecar 命令时生效；'
                      '修改 TargetDir 或换源需要重新创建/加入库。',
                      style: TextStyle(fontSize: 10.5, color: AppColors.faint),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SectionCard(
                title: '核心与完整性',
                subtitle: '所有数据事实以 sidecar JSON 为准',
                child: Column(
                  children: [
                    InfoRow(
                      label: '核心版本',
                      value: runtime?.version ?? '不可用',
                      mono: true,
                    ),
                    const Divider(),
                    InfoRow(
                      label: 'sidecar',
                      value: runtime?.binary.path ?? '—',
                      mono: true,
                      selectable: true,
                      trailing: _CopyButton(
                        value: runtime?.binary.path,
                        onCopy: _copy,
                      ),
                    ),
                    const Divider(),
                    InfoRow(
                      label: '完整性',
                      value: switch (runtime?.integrity.status) {
                        CoreIntegrityStatus.verified => '已校验',
                        CoreIntegrityStatus.notPinned => '开发构建 · 未固定哈希',
                        CoreIntegrityStatus.mismatch => '不匹配 · 已阻止执行',
                        CoreIntegrityStatus.missing => '缺失',
                        null => '—',
                      },
                      valueColor: runtime?.integrityOk == false
                          ? AppColors.danger
                          : AppColors.success,
                    ),
                    const Divider(),
                    InfoRow(
                      label: 'SHA-256',
                      value: runtime?.integrity.actualSha256 ?? '—',
                      mono: true,
                      valueColor: AppColors.faint,
                    ),
                    const Divider(),
                    InfoRow(
                      label: '客户端',
                      value:
                          'v${info.appVersion}+${info.appBuildNumber} · 契约 v${info.integrationContractVersion}',
                    ),
                    const Divider(),
                    InfoRow(
                      label: '平台',
                      value: controller.platform.platformLabel,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SectionCard(
                title: '安全',
                subtitle: '敏感操作需要重新确认',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ActionRow(
                      icon: Icons.key_rounded,
                      title: '导出 Armor Key',
                      description: '需要再次验证主密码；导出的字符串不会写入日志。',
                      button: OutlinedButton(
                        onPressed: busy ? null : _exportKey,
                        child: const Text('导出'),
                      ),
                    ),
                    const Divider(),
                    _ActionRow(
                      icon: Icons.construction_outlined,
                      title: '写锁诊断',
                      description: '检查 TargetDir/.eimmortal.lock 与控制锁；删除写锁属于高风险操作，需要明确确认。',
                      button: OutlinedButton(
                        onPressed: busy || _checkingLocks
                            ? null
                            : _diagnoseLocks,
                        child: Text(_checkingLocks ? '检查中…' : '检查'),
                      ),
                    ),
                    const Divider(),
                    _ActionRow(
                      icon: Icons.lock_outline_rounded,
                      title: '立即锁定',
                      description: '清除内存中的主密码并返回解锁页。',
                      button: OutlinedButton(
                        onPressed: busy ? null : _lock,
                        child: const Text('锁定'),
                      ),
                    ),
                    const Divider(),
                    _ActionRow(
                      icon: Icons.delete_outline_rounded,
                      title: '移除本地配置',
                      description: '删除 profile、config.toml 与本地控制平面（vault）；TargetDir 不会被删除。',
                      danger: true,
                      button: OutlinedButton(
                        onPressed: busy ? null : _forgetProfile,
                        child: Text(
                          '移除',
                          style: TextStyle(color: AppColors.danger),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SectionCard(
                title: '应用',
                subtitle: '本地数据与退出',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InfoRow(
                      label: '应用数据',
                      value: controller.paths.root,
                      mono: true,
                      selectable: true,
                      trailing: IconButton(
                        onPressed: () => controller.platform.revealPath(
                          controller.paths.root,
                        ),
                        icon: const Icon(Icons.folder_open_rounded, size: 16),
                        tooltip: '打开应用数据目录',
                      ),
                    ),
                    const Divider(),
                    const InfoRow(
                      label: '日志',
                      value: '只保留在内存；不写文件、不包含 Armor Key / 主密码',
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: busy ? null : _quit,
                          icon: const Icon(Icons.logout_rounded, size: 16),
                          label: const Text('退出应用'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => controller.platform.revealPath(
                            controller.paths.root,
                          ),
                          child: const Text('打开应用数据目录'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.value, required this.onCopy});

  final String? value;
  final Future<void> Function(String) onCopy;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: value == null ? null : () => onCopy(value!),
      icon: const Icon(Icons.copy_rounded, size: 15),
      tooltip: '复制',
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.button,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget button;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 17,
            color: danger ? AppColors.danger : AppColors.accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: AppColors.faint,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          button,
        ],
      ),
    );
  }
}

class _ForgetProfileDialog extends StatefulWidget {
  const _ForgetProfileDialog({required this.targetDir});

  final String targetDir;

  @override
  State<_ForgetProfileDialog> createState() => _ForgetProfileDialogState();
}

class _ForgetProfileDialogState extends State<_ForgetProfileDialog> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('移除本地配置？'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '会删除 profile.json、config.toml 和应用数据目录里的本地控制平面（vault）。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'TargetDir 和其中的备份不会被删除。重新加入需要 Armor Key 与主密码。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.targetDir,
              style: TextStyle(
                fontFamily: 'Menlo',
                fontSize: 10.5,
                color: AppColors.faint,
              ),
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _confirmed,
              onChanged: (value) => setState(() => _confirmed = value ?? false),
              title: Text(
                '我明白需要 Armor Key + 主密码才能重新加入',
                style: TextStyle(fontSize: 12, color: AppColors.text),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _confirmed ? () => Navigator.pop(context, true) : null,
          child: const Text('确认移除'),
        ),
      ],
    );
  }
}

class _ExportKeyDialog extends StatefulWidget {
  const _ExportKeyDialog({required this.session});

  final VaultSession session;

  @override
  State<_ExportKeyDialog> createState() => _ExportKeyDialogState();
}

class _ExportKeyDialogState extends State<_ExportKeyDialog> {
  final TextEditingController _password = TextEditingController();
  bool _loading = false;
  String? _error;
  ExportKeyInfo? _key;

  @override
  void dispose() {
    _password
      ..text = ''
      ..dispose();
    _key = null;
    super.dispose();
  }

  Future<void> _verifyAndExport() async {
    if (_loading) return;
    final password = _password.text;
    if (password.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final probe = await widget.session.verifyPassword(password);
      if (!probe.isSuccess || probe.protocolError || probe.jsonList == null) {
        setState(() {
          _loading = false;
          _error = probe.isSuccess
              ? '主密码验证返回了异常结构。'
              : '主密码错误，或 vault.meta 损坏（exit ${probe.exitCode}）。';
        });
        return;
      }
      final result = await widget.session.exportKey();
      final key = exportKeyFromResult(result);
      if (!result.isSuccess || key == null) {
        setState(() {
          _loading = false;
          _error = '导出失败：${result.errorSummary}';
        });
        return;
      }
      setState(() {
        _loading = false;
        _key = key;
        _password.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制；注意云剪贴板与输入法可能记录。')));
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('导出 Armor Key'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: key == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Armor Key 用于在另一台机器恢复数据。请再次输入主密码确认是你本人。',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.6,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofocus: true,
                      enabled: !_loading,
                      onSubmitted: (_) => _verifyAndExport(),
                      decoration: const InputDecoration(labelText: '主密码'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NoticeBanner(
                      title: '只保存在内存与剪贴板',
                      message: '不要把 Armor Key 发到聊天工具或写入明文文件；建议保存到密码管理器。',
                      color: AppColors.amber,
                      icon: Icons.key_rounded,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '单行版',
                      style: TextStyle(fontSize: 11, color: AppColors.faint),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      key.armor,
                      style: TextStyle(
                        fontFamily: 'Menlo',
                        fontSize: 11.5,
                        height: 1.6,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _copy(key.armor),
                      icon: const Icon(Icons.copy_rounded, size: 15),
                      label: const Text('复制单行版'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '分组版（便于打印/手抄）',
                      style: TextStyle(fontSize: 11, color: AppColors.faint),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      key.grouped,
                      style: TextStyle(
                        fontFamily: 'Menlo',
                        fontSize: 10.5,
                        height: 1.6,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(key == null ? '取消' : '关闭'),
        ),
        if (key == null)
          FilledButton(
            onPressed: _loading ? null : _verifyAndExport,
            child: Text(_loading ? '验证中…' : '验证并导出'),
          )
        else
          FilledButton.icon(
            onPressed: () => _copy(key.armor),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('复制 Armor Key'),
          ),
      ],
    );
  }
}

class _LockDiagnosticsDialog extends StatefulWidget {
  const _LockDiagnosticsDialog({
    required this.target,
    required this.controlLocked,
    required this.vaultDir,
  });

  final TargetLockInfo target;
  final bool controlLocked;
  final String vaultDir;

  @override
  State<_LockDiagnosticsDialog> createState() => _LockDiagnosticsDialogState();
}

class _LockDiagnosticsDialogState extends State<_LockDiagnosticsDialog> {
  late TargetLockInfo _target = widget.target;
  late bool _controlLocked = widget.controlLocked;
  String? _message;

  Future<void> _deleteTargetLock() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('删除 TargetDir 写锁？'),
        content: const Text(
          '只有在你确认没有其他 eimmortal/备份进程写入该目录时才应删除。'
          '删除正在使用的锁可能导致并发写入损坏数据。优先使用 backup --break-lock 重试。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TargetLockInfo.delete(p.dirname(_target.path));
      final next = await TargetLockInfo.inspect(p.dirname(_target.path));
      setState(() {
        _target = next;
        _message = 'TargetDir 写锁已删除。';
      });
    } catch (error) {
      setState(() => _message = '删除失败：$error');
    }
  }

  Future<void> _deleteControlMarker() async {
    if (!Platform.isWindows) return;
    try {
      await ControlLockInfo.deleteMarker(widget.vaultDir);
      setState(() {
        _controlLocked = false;
        _message = 'Windows 控制锁标记已删除。';
      });
    } catch (error) {
      setState(() => _message = '删除失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('写锁诊断'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NoticeBanner(
                title: _target.locked
                    ? '检测到 TargetDir 写锁'
                    : '未检测到 TargetDir 写锁',
                message: _target.locked
                    ? '可能是上次写入被中断留下的。请先确认没有其他进程在运行。'
                    : '写入锁当前不存在。',
                color: _target.locked ? AppColors.amber : AppColors.success,
                icon: _target.locked
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline_rounded,
              ),
              const SizedBox(height: 14),
              InfoRow(
                label: '锁文件',
                value: _target.path,
                mono: true,
                selectable: true,
              ),
              if (_target.exists) ...[
                const Divider(),
                InfoRow(
                  label: 'host / pid',
                  value: '${_target.hostId ?? '?'} / ${_target.pid ?? '?'}',
                ),
                const Divider(),
                InfoRow(
                  label: '开始时间',
                  value: _target.startedAt == null
                      ? '?'
                      : _target.startedAt!.toLocal().toString().substring(
                          0,
                          19,
                        ),
                ),
                if (_target.toolVersion != null) ...[
                  const Divider(),
                  InfoRow(
                    label: 'tool',
                    value: _target.toolVersion!,
                    mono: true,
                  ),
                ],
              ],
              const Divider(),
              InfoRow(
                label: '控制锁',
                value: _controlLocked ? '被占用（命令返回 E20）' : '可获取',
                valueColor: _controlLocked
                    ? AppColors.danger
                    : AppColors.success,
              ),
              const SizedBox(height: 8),
              Text(
                Platform.isWindows
                    ? 'Windows 控制锁是 O_EXCL 标记文件；崩溃后可能残留，需要在确认没有进程后删除。'
                    : 'Unix 控制锁是 flock；文件存在不代表被占用，删除文件不会释放锁。',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: AppColors.faint,
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 10),
                Text(
                  _message!,
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        if (_target.locked)
          OutlinedButton(
            onPressed: _deleteTargetLock,
            child: Text(
              '删除 TargetDir 写锁',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        if (Platform.isWindows && _controlLocked)
          FilledButton(
            onPressed: _deleteControlMarker,
            child: const Text('删除控制锁标记'),
          ),
      ],
    );
  }
}
