import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/vault_settings.dart';
import '../theme.dart';
import 'section_card.dart';

/// 普通参数 + 高级参数的共用编辑器；onboarding 与设置页使用同一份校验逻辑。
class VaultSettingsForm extends StatefulWidget {
  const VaultSettingsForm({
    required this.initial,
    required this.onChanged,
    this.enabled = true,
    this.showAdvanced = true,
    super.key,
  });

  final VaultSettings initial;
  final ValueChanged<VaultSettings> onChanged;
  final bool enabled;
  final bool showAdvanced;

  @override
  State<VaultSettingsForm> createState() => VaultSettingsFormState();
}

class VaultSettingsFormState extends State<VaultSettingsForm> {
  late final TextEditingController _session;
  late final TextEditingController _pack;
  late final TextEditingController _slice;
  late final TextEditingController _small;
  late final TextEditingController _minCompress;
  late final TextEditingController _sparse;
  late final TextEditingController _staging;
  late final TextEditingController _exclude;

  late int _zstd;
  late String _scanMode;
  late String _hardlinks;
  late String _onChange;
  late bool _ignoreXattr;
  String? _error;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _session = TextEditingController();
    _pack = TextEditingController();
    _slice = TextEditingController();
    _small = TextEditingController();
    _minCompress = TextEditingController();
    _sparse = TextEditingController();
    _staging = TextEditingController();
    _exclude = TextEditingController();
    for (final controller in [
      _session,
      _pack,
      _slice,
      _small,
      _minCompress,
      _sparse,
      _staging,
      _exclude,
    ]) {
      controller.addListener(_emit);
    }
    _apply(widget.initial);
  }

  void _apply(VaultSettings settings) {
    _applying = true;
    _session.text = '${settings.sessionMaxMib}';
    _pack.text = '${settings.packMaxMiB}';
    _slice.text = '${settings.slicePlainMiB}';
    _small.text = '${settings.smallFileMiB}';
    _minCompress.text = '${settings.minCompressKiB}';
    _sparse.text = '${settings.sparseMaxMiB}';
    _staging.text = settings.stagingDir;
    _exclude.text = settings.excludeRules.join('\n');
    _zstd = settings.zstdLevel;
    _scanMode = settings.scanMode;
    _hardlinks = settings.followHardlinks;
    _onChange = settings.onChangeStrategy;
    _ignoreXattr = settings.ignoreXattr;
    _error = null;
    _applying = false;
  }

  @override
  void dispose() {
    for (final controller in [
      _session,
      _pack,
      _slice,
      _small,
      _minCompress,
      _sparse,
      _staging,
      _exclude,
    ]) {
      controller
        ..removeListener(_emit)
        ..dispose();
    }
    super.dispose();
  }

  int _parse(TextEditingController controller) {
    return int.tryParse(controller.text.trim()) ?? -1;
  }

  VaultSettings read() {
    return VaultSettings(
      packMaxMiB: _parse(_pack),
      slicePlainMiB: _parse(_slice),
      smallFileMiB: _parse(_small),
      sessionMaxMib: _parse(_session),
      zstdLevel: _zstd,
      minCompressKiB: _parse(_minCompress),
      scanMode: _scanMode,
      excludeRules: List<String>.unmodifiable(
        _exclude.text
            .split('\n')
            .map((rule) => rule.trim())
            .where((rule) => rule.isNotEmpty),
      ),
      followHardlinks: _hardlinks,
      ignoreXattr: _ignoreXattr,
      sparseMaxMiB: _parse(_sparse),
      onChangeStrategy: _onChange,
      stagingDir: _staging.text.trim(),
    );
  }

  String? validate() {
    final error = read().validate();
    if (mounted) setState(() => _error = error);
    return error;
  }

  void resetToDefaults() {
    _apply(const VaultSettings());
    setState(() {});
    _emit();
  }

  void _emit() {
    if (_applying) return;
    widget.onChanged(read());
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _pickStaging() async {
    final path = await getDirectoryPath(confirmButtonText: '选择暂存目录');
    if (path == null || !mounted) return;
    _staging.text = path;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '普通参数',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            TextButton(
              onPressed: widget.enabled ? resetToDefaults : null,
              child: const Text('恢复推荐值'),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '影响每次备份的默认行为；修改后写入本地 config.toml，下次命令生效。',
          style: TextStyle(fontSize: 11, height: 1.5, color: AppColors.faint),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 620;
            final session = _NumberField(
              controller: _session,
              enabled: widget.enabled,
              label: '单次备份上限',
              suffix: 'MiB',
              helper: '默认 50 GB（51200 MiB）；达到上限会截断本次提交',
            );
            final compression = _SliderField(
              label: '压缩级别',
              value: _zstd,
              enabled: widget.enabled,
              onChanged: (value) {
                setState(() => _zstd = value);
                _emit();
              },
            );
            if (!twoColumns) {
              return Column(
                children: [session, const SizedBox(height: 14), compression],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: session),
                const SizedBox(width: 14),
                Expanded(child: compression),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Text('扫描模式', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'fast',
              label: Text('快速'),
              icon: Icon(Icons.bolt_rounded, size: 15),
            ),
            ButtonSegment(
              value: 'strict',
              label: Text('严格'),
              icon: Icon(Icons.fingerprint_rounded, size: 15),
            ),
          ],
          selected: {_scanMode},
          showSelectedIcon: false,
          style: ButtonStyle(
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
            iconColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? AppColors.onAccent
                  : AppColors.muted;
            }),
            overlayColor: WidgetStatePropertyAll(
              AppColors.accent.withValues(alpha: 0.12),
            ),
            side: WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          onSelectionChanged: widget.enabled
              ? (values) {
                  setState(() => _scanMode = values.first);
                  _emit();
                }
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          _scanMode == 'strict'
              ? '每次备份都会读取并 hash 全部文件，慢但不怕 mtime 被篡改。'
              : '默认。用 mtime + size 判断变化，速度更快。',
          style: TextStyle(fontSize: 10.5, height: 1.5, color: AppColors.faint),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _exclude,
          enabled: widget.enabled,
          minLines: 3,
          maxLines: 6,
          style: const TextStyle(
            fontFamily: 'Menlo',
            fontFamilyFallback: ['Consolas', 'Courier New'],
            fontSize: 11.5,
            height: 1.5,
          ),
          decoration: const InputDecoration(
            labelText: '排除规则（每行一条 glob，相对源目录）',
            hintText: '*.tmp\nnode_modules/**\n.DS_Store',
            helperText: '空列表表示不排除；以 # 开头的行不会被当成注释，请直接删掉',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          NoticeBanner(
            title: '参数不合法',
            message: _error!,
            color: AppColors.danger,
            icon: Icons.error_outline_rounded,
          ),
        ],
        if (widget.showAdvanced) ...[
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSoft),
            ),
            child: Material(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                iconColor: AppColors.muted,
                collapsedIconColor: AppColors.muted,
                title: Text(
                  '高级参数',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                subtitle: Text(
                  'pack/slice 尺寸、暂存目录、xattr 与硬链接策略；不了解时保持默认',
                  style: TextStyle(fontSize: 10.5, color: AppColors.faint),
                ),
                children: _buildAdvanced(context),
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildAdvanced(BuildContext context) {
    return [
      const SizedBox(height: 4),
      NoticeBanner(
        title: '结构参数只影响后续备份',
        message:
            'pack/slice/small_file 会被记入每次提交的参数快照；已有快照仍可读取。'
            '调小 pack 会让同步/重传粒度更细，但 pack 数量更多。',
        color: AppColors.amber,
        icon: Icons.warning_amber_rounded,
      ),
      const SizedBox(height: 14),
      LayoutBuilder(
        builder: (context, constraints) {
          final two = constraints.maxWidth >= 620;
          final fields = [
            _NumberField(
              controller: _pack,
              enabled: widget.enabled,
              label: 'pack 上限',
              suffix: 'MiB',
              helper: '单个 pack 文件上限',
            ),
            _NumberField(
              controller: _slice,
              enabled: widget.enabled,
              label: 'slice 上限',
              suffix: 'MiB',
              helper: '1..64，随机读取粒度',
            ),
            _NumberField(
              controller: _small,
              enabled: widget.enabled,
              label: '小文件阈值',
              suffix: 'MiB',
              helper: '不超过此值整文件进 pack',
            ),
            _NumberField(
              controller: _minCompress,
              enabled: widget.enabled,
              label: '最小压缩阈值',
              suffix: 'KiB',
              helper: '0..1024，小切片不压缩',
            ),
            _NumberField(
              controller: _sparse,
              enabled: widget.enabled,
              label: '稀疏文件上限',
              suffix: 'MiB',
              helper: '0 表示遇到稀疏文件即报错',
            ),
          ];
          if (!two) {
            return Column(
              children: [
                for (var index = 0; index < fields.length; index++) ...[
                  if (index > 0) const SizedBox(height: 12),
                  fields[index],
                ],
              ],
            );
          }
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 12),
                  Expanded(child: fields[1]),
                  const SizedBox(width: 12),
                  Expanded(child: fields[2]),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: fields[3]),
                  const SizedBox(width: 12),
                  Expanded(child: fields[4]),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '约束：slice + 50B、small_file + 50B 都必须 ≤ pack。',
                style: TextStyle(fontSize: 10.5, color: AppColors.faint),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _staging,
              enabled: widget.enabled,
              style: const TextStyle(
                fontFamily: 'Menlo',
                fontFamilyFallback: ['Consolas', 'Courier New'],
                fontSize: 11.5,
              ),
              decoration: const InputDecoration(
                labelText: '暂存目录（可选）',
                hintText: '留空 = <TargetDir>.tmp',
                helperText: '必须与 TargetDir 同卷，且不在同步范围内',
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: widget.enabled ? _pickStaging : null,
            child: const Text('选择…'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _ignoreXattr,
        onChanged: widget.enabled
            ? (value) {
                setState(() => _ignoreXattr = value);
                _emit();
              }
            : null,
        title: const Text('忽略 xattr / ACL', style: TextStyle(fontSize: 12.5)),
        subtitle: const Text(
          'macOS 建议开启；关闭后带扩展属性的文件可能以 E21 失败',
          style: TextStyle(fontSize: 10.5),
        ),
      ),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (context, constraints) {
          final two = constraints.maxWidth >= 620;
          final hardlinks = DropdownButtonFormField<String>(
            key: ValueKey('hardlinks-$_hardlinks'),
            initialValue: _hardlinks,
            decoration: const InputDecoration(
              labelText: '硬链接',
              helperText: 'error 保留语义；split 接受拆分降级',
            ),
            items: const [
              DropdownMenuItem(value: 'error', child: Text('error · 报错')),
              DropdownMenuItem(value: 'split', child: Text('split · 拆分备份')),
            ],
            onChanged: widget.enabled
                ? (value) {
                    setState(() => _hardlinks = value ?? 'error');
                    _emit();
                  }
                : null,
          );
          final onChange = DropdownButtonFormField<String>(
            key: ValueKey('onchange-$_onChange'),
            initialValue: _onChange,
            decoration: const InputDecoration(
              labelText: '读取中源文件变化',
              helperText: 'retry / skip / fail',
            ),
            items: const [
              DropdownMenuItem(value: 'retry', child: Text('retry · 重试')),
              DropdownMenuItem(value: 'skip', child: Text('skip · 跳过并报告')),
              DropdownMenuItem(value: 'fail', child: Text('fail · 整次失败')),
            ],
            onChanged: widget.enabled
                ? (value) {
                    setState(() => _onChange = value ?? 'retry');
                    _emit();
                  }
                : null,
          );
          if (!two) {
            return Column(
              children: [hardlinks, const SizedBox(height: 12), onChange],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: hardlinks),
              const SizedBox(width: 12),
              Expanded(child: onChange),
            ],
          );
        },
      ),
    ];
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.enabled,
    required this.label,
    required this.suffix,
    required this.helper,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final String suffix;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      style: const TextStyle(
        fontFamily: 'Menlo',
        fontFamilyFallback: ['Consolas', 'Courier New'],
        fontSize: 12,
      ),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        helperText: helper,
        helperMaxLines: 2,
      ),
    );
  }
}

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12.5, color: AppColors.text),
            ),
            const Spacer(),
            Text(
              'zstd $value',
              style: TextStyle(
                fontFamily: 'Menlo',
                fontSize: 11.5,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: 1,
          max: 22,
          divisions: 21,
          label: '$value',
          onChanged: enabled ? (next) => onChanged(next.round()) : null,
        ),
        Text(
          '1 最快 / 5 均衡 / 19 长期归档',
          style: TextStyle(fontSize: 10, color: AppColors.faint),
        ),
      ],
    );
  }
}
