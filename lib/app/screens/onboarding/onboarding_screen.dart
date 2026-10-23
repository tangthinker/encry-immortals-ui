import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app_controller.dart';
import '../../window_title.dart';
import '../../../core/core_models.dart';
import '../../../core/onboarding_service.dart';
import '../../../core/profile.dart';
import '../../../core/vault_settings.dart';
import '../../theme.dart';
import '../../widgets/app_mark.dart';
import '../../widgets/log_panel.dart';
import '../../widgets/section_card.dart';
import '../../widgets/vault_settings_form.dart';

enum _Mode { choice, create, join, createSuccess, joinSuccess }

VaultSettings _defaultOnboardingSettings() {
  return VaultSettings(ignoreXattr: Platform.isMacOS);
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  _Mode _mode = _Mode.choice;
  int _step = 0;
  VaultSettings _settings = _defaultOnboardingSettings();
  GlobalKey<VaultSettingsFormState> _settingsKey =
      GlobalKey<VaultSettingsFormState>();

  String? _sourceRoot;
  String? _targetDir;
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final TextEditingController _armorKey = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  List<OnboardingStepResult> _steps = [];
  List<String> _logs = [];
  Profile? _pendingProfile;
  String? _pendingPassword;
  ExportKeyInfo? _key;
  bool _keyConfirmed = false;

  @override
  void initState() {
    super.initState();
    _mode = switch (widget.controller.workspaceSetupMode) {
      WorkspaceSetupMode.create => _Mode.create,
      WorkspaceSetupMode.import => _Mode.join,
      null => _Mode.choice,
    };
    _password.addListener(_onCredentialChanged);
    _confirm.addListener(_onCredentialChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setAppWindowTitle('欢迎');
    });
  }

  void _onCredentialChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _password.removeListener(_onCredentialChanged);
    _confirm.removeListener(_onCredentialChanged);
    _password
      ..text = ''
      ..dispose();
    _confirm
      ..text = ''
      ..dispose();
    _armorKey
      ..text = ''
      ..dispose();
    super.dispose();
  }

  void _resetForm() {
    _sourceRoot = null;
    _targetDir = null;
    _password.clear();
    _confirm.clear();
    _armorKey.clear();
    _step = 0;
    _error = null;
    _steps = [];
    _logs = [];
    _pendingProfile = null;
    _pendingPassword = null;
    _key = null;
    _keyConfirmed = false;
    _settings = _defaultOnboardingSettings();
    _settingsKey = GlobalKey<VaultSettingsFormState>();
  }

  Future<void> _pickDirectory({required bool source}) async {
    final path = await getDirectoryPath(
      confirmButtonText: source ? '选择源目录' : '选择 TargetDir',
    );
    if (path == null || !mounted) return;
    setState(() {
      if (source) {
        _sourceRoot = path;
      } else {
        _targetDir = path;
      }
      _error = null;
    });
  }

  String? _directoryError({required bool join}) {
    final source = _sourceRoot;
    final target = _targetDir;
    if (source == null) return '请选择要备份的源目录。';
    if (target == null) return '请选择 TargetDir。';
    if (!Directory(source).existsSync()) return '源目录不存在：$source';
    if (!Directory(target).existsSync()) return 'TargetDir 不存在：$target';
    final s = p.canonicalize(source);
    final t = p.canonicalize(target);
    if (p.equals(s, t) || p.isWithin(s, t) || p.isWithin(t, s)) {
      return '源目录与 TargetDir 不能相同或互相包含。';
    }
    if (join) {
      final hasData =
          Directory(p.join(t, 'meta')).existsSync() ||
          Directory(p.join(t, 'data')).existsSync();
      if (!hasData) {
        return 'TargetDir 里没有 meta/ 或 data/，不像 eimmortal 备份目录。';
      }
    } else {
      try {
        final entries = Directory(t)
            .listSync()
            .where((entry) => p.basename(entry.path) != '.DS_Store')
            .toList();
        if (entries.isNotEmpty) {
          return '新建工作区要求 TargetDir 为空；已有备份请使用“导入已有工作区”。';
        }
      } on FileSystemException catch (error) {
        return '无法读取 TargetDir：$error';
      }
    }
    return null;
  }

  String? _passwordError({bool requireConfirmation = true}) {
    final password = _password.text;
    if (utf8.encode(password).length < 12) {
      return '主密码至少需要 12 个字节，推荐 4 个以上随机单词。';
    }
    if (password.contains('\n') || password.contains('\r')) {
      return '主密码不能包含换行。';
    }
    if (requireConfirmation && password != _confirm.text) {
      return '两次输入的主密码不一致。';
    }
    return null;
  }

  void _startCreate() {
    _resetForm();
    setState(() => _mode = _Mode.create);
  }

  void _startJoin() {
    _resetForm();
    setState(() => _mode = _Mode.join);
  }

  void _next() {
    if (_busy) return;
    final isJoin = _mode == _Mode.join;
    String? error;
    if (_step == 0) {
      error = _directoryError(join: isJoin);
    } else if (_step == 1) {
      error = _passwordError(requireConfirmation: !isJoin);
    } else if (_step == 2) {
      final form = _settingsKey.currentState;
      final settings = form?.read() ?? _settings;
      error = form?.validate() ?? settings.validate();
      if (error == null) _settings = settings;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _error = null;
      _step++;
    });
  }

  Future<void> _back() async {
    if (_busy) return;
    if (_step == 0 && widget.controller.workspaceSetupMode != null) {
      try {
        await widget.controller.cancelWorkspaceSetup();
      } catch (error) {
        if (mounted) setState(() => _error = '$error');
      }
      return;
    }
    if (_step == 0) {
      setState(() {
        _mode = _Mode.choice;
        _error = null;
      });
      return;
    }
    setState(() {
      _step--;
      _error = null;
    });
  }

  Future<void> _create() async {
    final source = _sourceRoot!;
    final target = _targetDir!;
    final password = _password.text;
    setState(() {
      _busy = true;
      _error = null;
      _steps = [];
      _logs = [];
    });
    final result = await widget.controller.createVault(
      sourceRoot: source,
      targetDir: target,
      password: password,
      settings: _settings,
      onLog: _appendLog,
      onStep: _appendStep,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.success && result.profile != null && result.key != null) {
        _pendingProfile = result.profile;
        _pendingPassword = password;
        _key = result.key;
        _mode = _Mode.createSuccess;
        _step = 0;
      } else {
        _error = result.error ?? '创建失败。';
      }
    });
  }

  Future<void> _join() async {
    final source = _sourceRoot!;
    final target = _targetDir!;
    final password = _password.text;
    final armorKey = _armorKey.text.trim();
    if (!armorKey.startsWith('EIMMORTAL-KEY-V2-')) {
      setState(() => _error = 'Armor Key 格式不正确。');
      return;
    }
    final passwordError = _passwordError(requireConfirmation: false);
    if (passwordError != null) {
      setState(() => _error = passwordError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _steps = [];
      _logs = [];
    });
    final result = await widget.controller.joinVault(
      sourceRoot: source,
      targetDir: target,
      armorKey: armorKey,
      password: password,
      settings: _settings,
      onLog: _appendLog,
      onStep: _appendStep,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.success && result.profile != null) {
        _pendingProfile = result.profile;
        _pendingPassword = password;
        _mode = _Mode.joinSuccess;
        _step = 0;
      } else {
        _error = result.error ?? '加入失败。';
      }
    });
  }

  void _appendStep(OnboardingStepResult step) {
    if (!mounted) return;
    setState(() => _steps = [..._steps, step]);
  }

  void _appendLog(String line) {
    if (!mounted) return;
    setState(() {
      _logs = [..._logs, line];
      if (_logs.length > 300) {
        _logs = _logs.sublist(_logs.length - 300);
      }
    });
  }

  Future<void> _activate() async {
    final profile = _pendingProfile;
    final password = _pendingPassword;
    if (profile == null || password == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await widget.controller.activateProfile(profile, password);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!outcome.success) {
        _error = outcome.message ?? '进入应用失败。';
      }
    });
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('取消当前操作？'),
        content: const Text('会终止正在运行的 sidecar，并清理本次尝试写入的本地控制平面。'),
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
    if (confirmed == true) await widget.controller.queue.cancelCurrent();
  }

  Future<void> _resetLocal() async {
    try {
      await widget.controller.resetLocalConfig();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: switch (_mode) {
              _Mode.choice => _buildChoice(),
              _Mode.create => _buildForm(isJoin: false),
              _Mode.join => _buildForm(isJoin: true),
              _Mode.createSuccess => _buildCreateSuccess(),
              _Mode.joinSuccess => _buildJoinSuccess(),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildChoice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const AppMark(size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Encry Immortals',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '本地优先的加密增量备份',
                    style: TextStyle(fontSize: 12, color: AppColors.faint),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => widget.controller.quit(),
              child: const Text('退出'),
            ),
          ],
        ),
        const SizedBox(height: 36),
        Text(
          '新建或导入工作区',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '新建一个工作区，或从另一台机器带来的 Armor Key 导入已有备份。'
          '每个工作区拥有独立的 profile、config.toml 和本地控制平面。',
          style: TextStyle(fontSize: 13, height: 1.6, color: AppColors.muted),
        ),
        const SizedBox(height: 26),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final create = _ChoiceCard(
              icon: Icons.add_circle_outline_rounded,
              color: AppColors.accent,
              title: '新建工作区',
              description: '选择一个源目录和一个空的 TargetDir，设置主密码并生成 Armor Key。',
              bullets: const [
                'TargetDir 建议放在网盘同步目录',
                '源根目录会被固定，之后不能随意更换',
                '创建后请立刻保存 Armor Key',
              ],
              onTap: _startCreate,
            );
            final join = _ChoiceCard(
              icon: Icons.link_rounded,
              color: AppColors.blue,
              title: '导入已有工作区',
              description: '选择已有 TargetDir，粘贴另一台机器的 Armor Key，再用主密码验证。',
              bullets: const [
                '不会重新加密已有数据',
                '需要 Armor Key 与主密码',
                '加入后会先跑 doctor --chain',
              ],
              onTap: _startJoin,
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: create),
                  const SizedBox(width: 18),
                  Expanded(child: join),
                ],
              );
            }
            return Column(children: [create, const SizedBox(height: 14), join]);
          },
        ),
        const SizedBox(height: 26),
        NoticeBanner(
          title: '安全提示',
          message:
              '主密码不可更改；忘记密码将无法恢复。Armor Key 只包含盐与 KDF 参数，'
              '但仍应与主密码分开保存。应用不会把你的密码写入磁盘或日志。'
              'macOS 首次读取“桌面/文稿”等受保护目录时可能要求完全磁盘访问权限。',
          icon: Icons.shield_outlined,
          color: AppColors.blue,
        ),
        const SizedBox(height: 18),
        SelectableText(
          'sidecar: ${widget.controller.runtime?.version ?? '不可用'} · '
          'app data: ${widget.controller.paths.root}',
          style: TextStyle(
            fontFamily: 'Menlo',
            fontSize: 10.5,
            color: AppColors.faint,
          ),
        ),
      ],
    );
  }

  Widget _buildForm({required bool isJoin}) {
    final steps = isJoin
        ? const ['选择目录', '密码 / Key', '参数设置', '加入']
        : const ['选择目录', '主密码', '参数设置', '创建'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const AppMark(size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isJoin ? '导入已有工作区' : '新建工作区',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _back,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: Text(
                _step == 0
                    ? widget.controller.workspaceSetupMode != null
                          ? '返回工作区'
                          : '返回选择'
                    : '上一步',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _StepHeader(steps: steps, current: _step),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step == 0) _buildDirectoryStep(isJoin: isJoin),
              if (_step == 1) _buildCredentialStep(isJoin: isJoin),
              if (_step == 2) _buildParameterStep(isJoin: isJoin),
              if (_step == 3) _buildReviewStep(isJoin: isJoin),
              if (_error != null) ...[
                const SizedBox(height: 16),
                NoticeBanner(
                  title: '无法继续',
                  message: _error!,
                  color: AppColors.danger,
                  icon: Icons.error_outline_rounded,
                ),
              ],
              if (_busy || _steps.isNotEmpty || _logs.isNotEmpty) ...[
                const SizedBox(height: 18),
                _ProgressPanel(
                  steps: _steps,
                  logs: _logs,
                  busy: _busy,
                  error: _error,
                  onCancel: _busy ? _cancel : null,
                ),
              ],
              if (!_busy && _error != null && _mode != _Mode.choice) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _resetLocal,
                    child: Text(
                      '重置本地配置后重试',
                      style: TextStyle(color: AppColors.danger, fontSize: 12),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              _buildNavButtons(isJoin: isJoin),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDirectoryStep({required bool isJoin}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FieldLabel('源目录', '需要备份的本地目录；创建后固定，不能在同一 TargetDir 上更换。'),
        _PathPicker(
          value: _sourceRoot,
          hint: '选择要备份的源目录',
          onPick: () => _pickDirectory(source: true),
          enabled: !_busy,
        ),
        const SizedBox(height: 20),
        _FieldLabel(
          'TargetDir',
          isJoin ? '已有备份目录，必须包含 meta/ 或 data/。' : '空目录，建议放在网盘同步目录中。',
        ),
        _PathPicker(
          value: _targetDir,
          hint: isJoin ? '选择已有备份目录' : '选择空的备份目录',
          onPick: () => _pickDirectory(source: false),
          enabled: !_busy,
        ),
        if (isJoin) ...[
          const SizedBox(height: 16),
          NoticeBanner(
            message: '加入前请确认 TargetDir 来自可信来源。应用不会在这里重新生成密钥。',
            color: AppColors.blue,
            icon: Icons.info_outline_rounded,
          ),
        ],
      ],
    );
  }

  Widget _buildCredentialStep({required bool isJoin}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isJoin) ...[
          const _FieldLabel(
            'Armor Key',
            '从原机器导出，通常以 EIMMORTAL-KEY-V2- 开头；可以粘贴分组版。',
          ),
          TextField(
            controller: _armorKey,
            enabled: !_busy,
            minLines: 2,
            maxLines: 5,
            style: const TextStyle(
              fontFamily: 'Menlo',
              fontSize: 11.5,
              height: 1.55,
            ),
            decoration: const InputDecoration(
              hintText: 'EIMMORTAL-KEY-V2-… 或分组的 5 字符块',
            ),
          ),
          const SizedBox(height: 20),
        ],
        const _FieldLabel('主密码', '至少 12 个字节；只用于解锁，不会保存。'),
        TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: _obscure,
          decoration: InputDecoration(
            hintText: isJoin ? '输入该库的主密码' : '设置主密码',
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
                color: AppColors.faint,
              ),
            ),
          ),
        ),
        if (!isJoin) ...[
          const SizedBox(height: 16),
          const _FieldLabel('确认主密码', '两次输入必须一致；主密码不可更改。'),
          TextField(
            controller: _confirm,
            enabled: !_busy,
            obscureText: _obscure,
            decoration: const InputDecoration(hintText: '再次输入主密码'),
          ),
          const SizedBox(height: 16),
          _PasswordChecklist(password: _password.text, confirm: _confirm.text),
        ],
      ],
    );
  }

  Widget _buildParameterStep({required bool isJoin}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '参数设置',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isJoin
              ? '加入后这些参数会写入本地 config.toml，只影响这台机器后续的备份/恢复操作。'
              : '这些参数会写入本地 config.toml，之后可在“设置”中继续调整。',
          style: TextStyle(fontSize: 11.5, height: 1.6, color: AppColors.faint),
        ),
        const SizedBox(height: 18),
        VaultSettingsForm(
          key: _settingsKey,
          initial: _settings,
          enabled: !_busy,
          onChanged: (value) {
            _settings = value;
            if (_error != null) setState(() => _error = null);
          },
        ),
      ],
    );
  }

  Widget _buildReviewStep({required bool isJoin}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '确认信息',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 16),
        InfoRow(
          label: '源目录',
          value: _sourceRoot ?? '—',
          mono: true,
          selectable: true,
        ),
        const Divider(),
        InfoRow(
          label: 'TargetDir',
          value: _targetDir ?? '—',
          mono: true,
          selectable: true,
        ),
        if (isJoin) ...[
          const Divider(),
          InfoRow(
            label: 'Armor Key',
            value: '已输入（${_armorKey.text.trim().length} 字符）',
            valueColor: AppColors.accent,
          ),
        ],
        const Divider(),
        InfoRow(
          label: '普通参数',
          value:
              '上限 ${_settings.sessionMaxMib} MiB · zstd ${_settings.zstdLevel} · '
              '${_settings.scanModeLabel} · 排除 ${_settings.excludeRules.length} 条',
        ),
        const Divider(),
        InfoRow(
          label: '高级参数',
          value:
              'pack ${_settings.packMaxMiB} MiB · slice ${_settings.slicePlainMiB} MiB · '
              'small ${_settings.smallFileMiB} MiB',
        ),
        const SizedBox(height: 16),
        NoticeBanner(
          message:
              '开始后会在本地应用数据目录创建控制平面。失败会自动清理本地控制平面，'
              '不会删除 TargetDir 中的备份。',
          color: AppColors.amber,
          icon: Icons.warning_amber_rounded,
        ),
      ],
    );
  }

  Widget _buildNavButtons({required bool isJoin}) {
    final isLast = _step == 3;
    return Row(
      children: [
        if (_step > 0)
          OutlinedButton(
            onPressed: _busy ? null : _back,
            child: const Text('上一步'),
          ),
        const Spacer(),
        if (!isLast)
          FilledButton(onPressed: _busy ? null : _next, child: const Text('继续'))
        else
          FilledButton.icon(
            onPressed: _busy
                ? null
                : isJoin
                ? _join
                : _create,
            icon: _busy
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onAccent,
                    ),
                  )
                : Icon(
                    isJoin
                        ? Icons.link_rounded
                        : Icons.add_circle_outline_rounded,
                    size: 18,
                  ),
            label: Text(
              _busy
                  ? (isJoin ? '正在加入…' : '正在创建…')
                  : (isJoin ? '加入备份库' : '创建备份库'),
            ),
          ),
      ],
    );
  }

  Widget _buildCreateSuccess() {
    final profile = _pendingProfile!;
    final key = _key!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const AppMark(size: 44),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '库已创建',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '下一步：保存 Armor Key，然后进入应用',
                    style: TextStyle(fontSize: 12, color: AppColors.faint),
                  ),
                ],
              ),
            ),
            StatusPill(
              label: 'vault.meta 已生成',
              color: AppColors.success,
              dense: true,
            ),
          ],
        ),
        const SizedBox(height: 22),
        NoticeBanner(
          title: '先保存 Armor Key',
          message:
              'Armor Key 是你换机器或重装后恢复数据的唯一凭据。它包含盐与 KDF 参数，'
              '请与主密码分开存放。关闭此页面后仍可在设置中再次导出，但需要主密码。',
          color: AppColors.amber,
          icon: Icons.key_rounded,
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '单行版',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.faint,
                ),
              ),
              const SizedBox(height: 8),
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
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _copy(key.armor),
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('复制单行版'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => _copy(key.grouped),
                    icon: const Icon(Icons.content_copy_rounded, size: 15),
                    label: const Text('复制分组版'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CheckboxListTile(
          value: _keyConfirmed,
          onChanged: (value) => setState(() => _keyConfirmed = value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(
            '我已把 Armor Key 保存到密码管理器或离线位置',
            style: TextStyle(fontSize: 12.5, color: AppColors.text),
          ),
          subtitle: Text(
            '没有 Armor Key，重装或换机后无法恢复数据。',
            style: TextStyle(fontSize: 11, color: AppColors.faint),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          NoticeBanner(
            title: '进入应用失败',
            message: _error!,
            color: AppColors.danger,
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Text(
              '${profile.sourceRoot} → ${profile.targetDir}',
              style: TextStyle(fontSize: 10.5, color: AppColors.faint),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _busy || !_keyConfirmed ? null : _activate,
              icon: _busy
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onAccent,
                      ),
                    )
                  : const Icon(Icons.arrow_forward_rounded, size: 17),
              label: const Text('进入应用'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildJoinSuccess() {
    final profile = _pendingProfile!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const AppMark(size: 44),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '已加入备份库',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'doctor --chain 已通过，可以查看历史或恢复数据。',
                    style: TextStyle(fontSize: 12, color: AppColors.faint),
                  ),
                ],
              ),
            ),
            StatusPill(label: '链校验通过', color: AppColors.success, dense: true),
          ],
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              InfoRow(
                label: '源目录',
                value: profile.sourceRoot,
                mono: true,
                selectable: true,
              ),
              const Divider(),
              InfoRow(
                label: 'TargetDir',
                value: profile.targetDir,
                mono: true,
                selectable: true,
              ),
              const Divider(),
              InfoRow(
                label: '本地控制平面',
                value: profile.vaultDir,
                mono: true,
                selectable: true,
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          NoticeBanner(
            title: '进入应用失败',
            message: _error!,
            color: AppColors.danger,
          ),
        ],
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _busy ? null : _activate,
            icon: _busy
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onAccent,
                    ),
                  )
                : const Icon(Icons.arrow_forward_rounded, size: 17),
            label: const Text('进入应用'),
          ),
        ),
      ],
    );
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制到剪贴板；注意云剪贴板/输入法可能记录。')));
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.bullets,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final List<String> bullets;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        hoverColor: AppColors.surfaceRaised,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 14),
              for (final bullet in bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_rounded, size: 14, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          bullet,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.5,
                            color: AppColors.faint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    '开始',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 15, color: color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.steps, required this.current});

  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < steps.length; index++) ...[
          if (index > 0)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: index <= current ? AppColors.accent : AppColors.border,
              ),
            ),
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: index <= current
                      ? AppColors.accent
                      : AppColors.surfaceRaised,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: index <= current
                        ? AppColors.accent
                        : AppColors.border,
                  ),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: index <= current
                          ? AppColors.onAccent
                          : AppColors.faint,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                steps[index],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: index == current
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: index <= current ? AppColors.text : AppColors.faint,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, this.help);

  final String label;
  final String help;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 3),
          Text(help, style: TextStyle(fontSize: 11, color: AppColors.faint)),
        ],
      ),
    );
  }
}

class _PathPicker extends StatelessWidget {
  const _PathPicker({
    required this.value,
    required this.hint,
    required this.onPick,
    required this.enabled,
  });

  final String? value;
  final String hint;
  final VoidCallback onPick;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            value == null ? Icons.folder_outlined : Icons.folder_rounded,
            size: 17,
            color: value == null ? AppColors.faint : AppColors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value ?? hint,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: value == null ? null : 'Menlo',
                fontSize: value == null ? 12 : 11.5,
                color: value == null ? AppColors.faint : AppColors.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: enabled ? onPick : null,
            child: const Text('选择…'),
          ),
        ],
      ),
    );
  }
}

class _PasswordChecklist extends StatelessWidget {
  const _PasswordChecklist({required this.password, required this.confirm});

  final String password;
  final String confirm;

  @override
  Widget build(BuildContext context) {
    final rules = [
      ('至少 12 个字节', utf8.encode(password).length >= 12),
      ('不含换行', !password.contains('\n') && !password.contains('\r')),
      ('两次输入一致', password.isNotEmpty && password == confirm),
    ];
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final rule in rules)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                rule.$2 ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 13,
                color: rule.$2 ? AppColors.success : AppColors.faint,
              ),
              const SizedBox(width: 5),
              Text(
                rule.$1,
                style: TextStyle(
                  fontSize: 11,
                  color: rule.$2 ? AppColors.muted : AppColors.faint,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({
    required this.steps,
    required this.logs,
    required this.busy,
    required this.error,
    this.onCancel,
  });

  final List<OnboardingStepResult> steps;
  final List<String> logs;
  final bool busy;
  final String? error;
  final VoidCallback? onCancel;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  error == null
                      ? Icons.check_circle_rounded
                      : Icons.error_outline,
                  size: 15,
                  color: error == null ? AppColors.success : AppColors.danger,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  busy
                      ? '正在执行：${steps.isEmpty ? '准备中' : '下一步'}'
                      : error == null
                      ? '完成'
                      : '已停止',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (onCancel != null)
                TextButton(onPressed: onCancel, child: const Text('取消')),
            ],
          ),
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final step in steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Icon(
                      step.ok ? Icons.check_rounded : Icons.close_rounded,
                      size: 13,
                      color: step.ok ? AppColors.success : AppColors.danger,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${step.label} · ${step.detail}',
                        style: TextStyle(
                          fontSize: 11,
                          color: step.ok ? AppColors.muted : AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (logs.isNotEmpty) ...[
            const SizedBox(height: 10),
            LogPanel(lines: logs, height: 150),
          ],
        ],
      ),
    );
  }
}
