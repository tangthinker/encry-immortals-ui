import 'package:path/path.dart' as p;

/// 与应用层共享的 sidecar 参数。存储大小时 UI 用 MiB/KiB，写 TOML 时换算成字节。
///
/// 只包含上游当前**实际读取**的参数；`concurrency.hashers`、`checkpoint.*`、
/// `verify.auto_strict_every` 等未实现字段不暴露，避免“设置无效”。
class VaultSettings {
  const VaultSettings({
    this.packMaxMiB = 128,
    this.slicePlainMiB = 32,
    this.smallFileMiB = 64,
    this.sessionMaxMib = 51200,
    this.zstdLevel = 5,
    this.minCompressKiB = 4,
    this.scanMode = 'fast',
    this.excludeRules = const [
      '.git/**',
      'node_modules/**',
      '*.tmp',
      '.DS_Store',
    ],
    this.followHardlinks = 'error',
    this.ignoreXattr = true,
    this.sparseMaxMiB = 0,
    this.onChangeStrategy = 'retry',
    this.stagingDir = '',
  });

  static const int mib = 1024 * 1024;

  final int packMaxMiB;
  final int slicePlainMiB;
  final int smallFileMiB;
  final int sessionMaxMib;
  final int zstdLevel;
  final int minCompressKiB;
  final String scanMode;
  final List<String> excludeRules;
  final String followHardlinks;
  final bool ignoreXattr;
  final int sparseMaxMiB;
  final String onChangeStrategy;
  final String stagingDir;

  int get packMaxBytes => packMaxMiB * mib;
  int get slicePlainBytes => slicePlainMiB * mib;
  int get smallFileBytes => smallFileMiB * mib;
  int get minCompressBytes => minCompressKiB * 1024;
  int get sparseMaxBytes => sparseMaxMiB * mib;

  String get scanModeLabel =>
      scanMode == 'strict' ? '严格（全量 hash）' : '快速（mtime + size）';

  String get followHardlinksLabel =>
      followHardlinks == 'split' ? '拆分备份（接受降级）' : '报错（保留语义）';

  String get onChangeStrategyLabel => switch (onChangeStrategy) {
    'skip' => '跳过并报告',
    'fail' => '整次失败',
    _ => '重试',
  };

  VaultSettings copyWith({
    int? packMaxMiB,
    int? slicePlainMiB,
    int? smallFileMiB,
    int? sessionMaxMib,
    int? zstdLevel,
    int? minCompressKiB,
    String? scanMode,
    List<String>? excludeRules,
    String? followHardlinks,
    bool? ignoreXattr,
    int? sparseMaxMiB,
    String? onChangeStrategy,
    String? stagingDir,
  }) {
    return VaultSettings(
      packMaxMiB: packMaxMiB ?? this.packMaxMiB,
      slicePlainMiB: slicePlainMiB ?? this.slicePlainMiB,
      smallFileMiB: smallFileMiB ?? this.smallFileMiB,
      sessionMaxMib: sessionMaxMib ?? this.sessionMaxMib,
      zstdLevel: zstdLevel ?? this.zstdLevel,
      minCompressKiB: minCompressKiB ?? this.minCompressKiB,
      scanMode: scanMode ?? this.scanMode,
      excludeRules: List<String>.unmodifiable(
        excludeRules ?? this.excludeRules,
      ),
      followHardlinks: followHardlinks ?? this.followHardlinks,
      ignoreXattr: ignoreXattr ?? this.ignoreXattr,
      sparseMaxMiB: sparseMaxMiB ?? this.sparseMaxMiB,
      onChangeStrategy: onChangeStrategy ?? this.onChangeStrategy,
      stagingDir: stagingDir ?? this.stagingDir,
    );
  }

  Map<String, Object?> toJson() => {
    'pack_max_mib': packMaxMiB,
    'slice_plain_mib': slicePlainMiB,
    'small_file_mib': smallFileMiB,
    'session_max_mib': sessionMaxMib,
    'zstd_level': zstdLevel,
    'min_compress_kib': minCompressKiB,
    'scan_mode': scanMode,
    'exclude': excludeRules,
    'follow_hardlinks': followHardlinks,
    'ignore_xattr': ignoreXattr,
    'sparse_max_mib': sparseMaxMiB,
    'on_change_strategy': onChangeStrategy,
    'staging_dir': stagingDir,
  };

  factory VaultSettings.fromJson(Map<String, Object?> json) {
    int integer(String key, int fallback) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? fallback;
    }

    String text(String key, String fallback) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : fallback;
    }

    final excludeRaw = json['exclude'];
    final exclude = excludeRaw is List
        ? excludeRaw.map((item) => '$item').toList(growable: false)
        : const ['.git/**', 'node_modules/**', '*.tmp', '.DS_Store'];

    return VaultSettings(
      packMaxMiB: integer('pack_max_mib', 128),
      slicePlainMiB: integer('slice_plain_mib', 32),
      smallFileMiB: integer('small_file_mib', 64),
      sessionMaxMib: integer('session_max_mib', 51200),
      zstdLevel: integer('zstd_level', 5),
      minCompressKiB: integer('min_compress_kib', 4),
      scanMode: text('scan_mode', 'fast'),
      excludeRules: List<String>.unmodifiable(exclude),
      followHardlinks: text('follow_hardlinks', 'error'),
      ignoreXattr: json['ignore_xattr'] != false,
      sparseMaxMiB: integer('sparse_max_mib', 0),
      onChangeStrategy: text('on_change_strategy', 'retry'),
      stagingDir: json['staging_dir'] is String
          ? json['staging_dir']! as String
          : '',
    );
  }

  /// 返回用户可读的错误；合法时返回 null。
  String? validate() {
    if (packMaxMiB < 1 || packMaxMiB > 16384) {
      return 'pack_max_mib 必须在 1..16384 之间。';
    }
    if (slicePlainMiB < 1 || slicePlainMiB > 64) {
      return 'slice_plain_mib 必须在 1..64 之间（线格式硬上限 64 MiB）。';
    }
    if (smallFileMiB < 1) {
      return 'small_file_mib 必须 ≥ 1。';
    }
    if (sessionMaxMib < 1 || sessionMaxMib > 1048576) {
      return 'session_max_mib 必须在 1..1048576 之间。';
    }
    if (zstdLevel < 1 || zstdLevel > 22) {
      return 'zstd_level 必须在 1..22 之间。';
    }
    if (minCompressKiB < 0 || minCompressKiB > 1024) {
      return 'min_compress_kib 必须在 0..1024 之间（0..1 MiB）。';
    }
    if (sparseMaxMiB < 0 || sparseMaxMiB > 1048576) {
      return 'sparse_max_mib 必须在 0..1048576 之间；0 表示不支持稀疏文件。';
    }
    if (scanMode != 'fast' && scanMode != 'strict') {
      return '扫描模式只能是 fast 或 strict。';
    }
    if (followHardlinks != 'error' && followHardlinks != 'split') {
      return '硬链接策略只能是 error 或 split。';
    }
    if (onChangeStrategy != 'retry' &&
        onChangeStrategy != 'skip' &&
        onChangeStrategy != 'fail') {
      return '读取中源文件变化策略只能是 retry/skip/fail。';
    }
    if (slicePlainBytes + 50 > packMaxBytes) {
      return 'slice_plain_mib + 50 字节超过 pack_max_mib。';
    }
    if (smallFileBytes + 50 > packMaxBytes) {
      return 'small_file_mib + 50 字节超过 pack_max_mib。';
    }
    final staging = stagingDir.trim();
    if (staging.contains('\n') || staging.contains('\r')) {
      return '暂存目录不能包含换行。';
    }
    if (staging.isNotEmpty &&
        !p.isAbsolute(staging) &&
        staging != '~' &&
        !staging.startsWith('~/')) {
      return '暂存目录必须是绝对路径（或 ~/ 开头），留空使用 <TargetDir>.tmp。';
    }
    if (excludeRules.length > 200) {
      return '排除规则最多 200 条。';
    }
    for (final rule in excludeRules) {
      if (rule.trim().isEmpty) return '排除规则不能为空行。';
      if (rule.contains('\n') || rule.contains('\r')) {
        return '排除规则不能包含换行。';
      }
    }
    return null;
  }

  /// 设置页/onboarding 的摘要行。
  List<(String, String)> get summaryRows => [
    ('单次上限', '$sessionMaxMib MiB'),
    ('压缩级别', 'zstd $zstdLevel'),
    ('扫描模式', scanMode == 'strict' ? 'strict' : 'fast'),
    ('排除规则', '${excludeRules.length} 条'),
    ('pack 上限', '$packMaxMiB MiB'),
    ('slice 上限', '$slicePlainMiB MiB'),
    ('小文件阈值', '$smallFileMiB MiB'),
  ];

  @override
  bool operator ==(Object other) {
    return other is VaultSettings &&
        other.packMaxMiB == packMaxMiB &&
        other.slicePlainMiB == slicePlainMiB &&
        other.smallFileMiB == smallFileMiB &&
        other.sessionMaxMib == sessionMaxMib &&
        other.zstdLevel == zstdLevel &&
        other.minCompressKiB == minCompressKiB &&
        other.scanMode == scanMode &&
        _sameRules(other.excludeRules, excludeRules) &&
        other.followHardlinks == followHardlinks &&
        other.ignoreXattr == ignoreXattr &&
        other.sparseMaxMiB == sparseMaxMiB &&
        other.onChangeStrategy == onChangeStrategy &&
        other.stagingDir == stagingDir;
  }

  @override
  int get hashCode => Object.hash(
    packMaxMiB,
    slicePlainMiB,
    smallFileMiB,
    sessionMaxMib,
    zstdLevel,
    minCompressKiB,
    scanMode,
    Object.hashAll(excludeRules),
    followHardlinks,
    ignoreXattr,
    sparseMaxMiB,
    onChangeStrategy,
    stagingDir,
  );

  static bool _sameRules(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}
