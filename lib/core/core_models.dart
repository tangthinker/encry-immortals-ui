/// CLI JSON 的 Dart 视图。字段全部按“缺失/未知字段不崩溃”处理。
library;

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry('$key', value));
  }
  return const <String, Object?>{};
}

Map<String, Object?> asJsonMap(Object? value) => _map(value);

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

bool _bool(Object? value) => value == true;

String _string(Object? value) => value == null ? '' : '$value';

List<String> _strings(Object? value) {
  if (value is! List) return const <String>[];
  return value.map((item) => '$item').toList(growable: false);
}

List<String>? _nullableStrings(Object? value) {
  if (value is! List) return null;
  return value.map((item) => '$item').toList(growable: false);
}

String parseCoreVersion(String stdout) {
  final match = RegExp(r'eimmortal\s+(\S+)').firstMatch(stdout);
  return match?.group(1) ?? stdout.trim();
}

/// `status --json`。
class VaultStatus {
  const VaultStatus({
    required this.schema,
    required this.vaultId,
    required this.lastSeq,
    required this.anchorShort,
    required this.verified,
    required this.localPacks,
    required this.referencedPacks,
    required this.orphanPacks,
    required this.missingPacks,
    required this.packTotalBytes,
    required this.journalTotalBytes,
    required this.stagingBytes,
    required this.logicalSourceBytes,
    required this.tmpEntries,
    required this.warnings,
  });

  final int schema;
  final String vaultId;
  final int lastSeq;
  final String anchorShort;
  final bool verified;
  final int localPacks;
  final int referencedPacks;
  final int orphanPacks;
  final int missingPacks;
  final int packTotalBytes;
  final int journalTotalBytes;
  final int stagingBytes;
  final int logicalSourceBytes;
  final int tmpEntries;
  final List<String> warnings;

  factory VaultStatus.fromJson(Map<String, Object?> json) {
    final packs = _map(json['packs']);
    final bytes = _map(json['bytes']);
    return VaultStatus(
      schema: _int(json['schema']),
      vaultId: _string(json['vault_id']),
      lastSeq: _int(json['last_seq']),
      anchorShort: _string(json['anchor_short']),
      verified: _bool(json['verified']),
      localPacks: _int(packs['local']),
      referencedPacks: _int(packs['referenced']),
      orphanPacks: _int(packs['orphan']),
      missingPacks: _int(packs['missing']),
      packTotalBytes: _int(bytes['pack_total']),
      journalTotalBytes: _int(bytes['journal_total']),
      stagingBytes: _int(bytes['staging']),
      logicalSourceBytes: _int(bytes['logical_source']),
      tmpEntries: _int(json['tmp_entries']),
      warnings: _strings(json['warnings']),
    );
  }

  /// 密码错误/链校验失败时 CLI 可能仍返回 exit 0 且 verified=true；
  /// 必须同时检查 warnings。
  bool get hasUnlockWarning => warnings.any(
    (warning) =>
        warning.contains('未能取得主密码') ||
        warning.contains('无法解锁') ||
        warning.contains('链校验失败') ||
        warning.contains('主密码'),
  );

  /// 未解锁时 referenced/logical_source 为 0，不能当成“库里没有数据”。
  bool get isUnlockedView =>
      verified && !hasUnlockWarning && (referencedPacks > 0 || lastSeq == 0);

  bool get isHealthy =>
      verified &&
      !hasUnlockWarning &&
      missingPacks == 0 &&
      orphanPacks == 0 &&
      tmpEntries == 0;

  List<String> get displayWarnings => List<String>.unmodifiable(warnings);
}

/// `log --json` 的一项。
class CommitEntry {
  const CommitEntry({
    required this.seq,
    required this.tsUnix,
    required this.kind,
    required this.message,
    required this.ops,
    required this.dirs,
    required this.packs,
    required this.journalSha256,
  });

  final int seq;
  final int tsUnix;
  final String kind;
  final String message;
  final int ops;
  final int dirs;
  final int packs;
  final String journalSha256;

  factory CommitEntry.fromJson(Map<String, Object?> json) {
    return CommitEntry(
      seq: _int(json['seq']),
      tsUnix: _int(json['ts_unix']),
      kind: _string(json['kind']),
      message: _string(json['msg']),
      ops: _int(json['ops']),
      dirs: _int(json['dirs']),
      packs: _int(json['packs']),
      journalSha256: _string(json['journal_sha256']),
    );
  }

  DateTime get timestamp =>
      DateTime.fromMillisecondsSinceEpoch(tsUnix * 1000);
}

/// `backup --json`。
class BackupSummary {
  const BackupSummary({
    required this.seq,
    required this.changed,
    required this.dryRun,
    required this.added,
    required this.modified,
    required this.deleted,
    required this.meta,
    required this.dirs,
    required this.links,
    required this.plainBytes,
    required this.packBytes,
    required this.journalBytes,
    required this.manifests,
    required this.truncated,
    required this.skipped,
  });

  final int seq;
  final bool changed;
  final bool dryRun;
  final int added;
  final int modified;
  final int deleted;
  final int meta;
  final int dirs;
  final int links;
  final int plainBytes;
  final int packBytes;
  final int journalBytes;
  final int manifests;
  final bool truncated;
  final int skipped;

  factory BackupSummary.fromJson(Map<String, Object?> json) {
    return BackupSummary(
      seq: _int(json['seq']),
      changed: _bool(json['changed']),
      dryRun: _bool(json['dry_run']),
      added: _int(json['added']),
      modified: _int(json['modified']),
      deleted: _int(json['deleted']),
      meta: _int(json['meta']),
      dirs: _int(json['dirs']),
      links: _int(json['links']),
      plainBytes: _int(json['plain_bytes']),
      packBytes: _int(json['pack_bytes']),
      journalBytes: _int(json['journal_bytes']),
      manifests: _int(json['manifests']),
      truncated: _bool(json['truncated']),
      skipped: _int(json['skipped']),
    );
  }

  bool get hasChanges => changed && seq > 0;
}

/// `restore --json`。
class RestoreSummary {
  const RestoreSummary({
    required this.seq,
    required this.files,
    required this.dirs,
    required this.links,
    required this.bytes,
    required this.skipped,
    required this.corrupt,
    required this.missingPacks,
    required this.missingFiles,
    required this.incomplete,
    required this.dryRun,
  });

  final int seq;
  final int files;
  final int dirs;
  final int links;
  final int bytes;
  final List<String>? skipped;
  final List<String>? corrupt;
  final List<String>? missingPacks;
  final List<String>? missingFiles;
  final bool incomplete;
  final bool dryRun;

  factory RestoreSummary.fromJson(Map<String, Object?> json) {
    return RestoreSummary(
      seq: _int(json['seq']),
      files: _int(json['files']),
      dirs: _int(json['dirs']),
      links: _int(json['links']),
      bytes: _int(json['bytes']),
      skipped: _nullableStrings(json['skipped']),
      corrupt: _nullableStrings(json['corrupt']),
      missingPacks: _nullableStrings(json['missing_packs']),
      missingFiles: _nullableStrings(json['missing_files']),
      incomplete: _bool(json['incomplete']),
      dryRun: _bool(json['dry_run']),
    );
  }
}

/// `verify --json`。
class VerifySummary {
  const VerifySummary({
    required this.localPacks,
    required this.referencedPacks,
    required this.missing,
    required this.sizeMismatch,
    required this.orphans,
    required this.sampled,
    required this.sampleFailures,
    required this.deepFiles,
    required this.deepBytes,
    required this.deepFailures,
  });

  final int localPacks;
  final int referencedPacks;
  final List<String>? missing;
  final List<String>? sizeMismatch;
  final int orphans;
  final int sampled;
  final List<String>? sampleFailures;
  final int deepFiles;
  final int deepBytes;
  final List<String>? deepFailures;

  factory VerifySummary.fromJson(Map<String, Object?> json) {
    return VerifySummary(
      localPacks: _int(json['local_packs']),
      referencedPacks: _int(json['referenced_packs']),
      missing: _nullableStrings(json['missing']),
      sizeMismatch: _nullableStrings(json['size_mismatch']),
      orphans: _int(json['orphans']),
      sampled: _int(json['sampled']),
      sampleFailures: _nullableStrings(json['sample_failures']),
      deepFiles: _int(json['deep_files']),
      deepBytes: _int(json['deep_bytes']),
      deepFailures: _nullableStrings(json['deep_failures']),
    );
  }

  bool get isClean =>
      (missing == null || missing!.isEmpty) &&
      (sizeMismatch == null || sizeMismatch!.isEmpty) &&
      (sampleFailures == null || sampleFailures!.isEmpty) &&
      (deepFailures == null || deepFailures!.isEmpty) &&
      orphans == 0;
}

enum DoctorStatus {
  pass,
  warn,
  fail,
  skip,
  unknown;

  static DoctorStatus parse(String value) {
    switch (value.toUpperCase()) {
      case 'PASS':
        return DoctorStatus.pass;
      case 'WARN':
        return DoctorStatus.warn;
      case 'FAIL':
        return DoctorStatus.fail;
      case 'SKIP':
        return DoctorStatus.skip;
      default:
        return DoctorStatus.unknown;
    }
  }

  String get label => switch (this) {
    pass => 'PASS',
    warn => 'WARN',
    fail => 'FAIL',
    skip => 'SKIP',
    unknown => '未知',
  };

  bool get isBlocking => this == fail;
}

class DoctorCheck {
  const DoctorCheck({
    required this.name,
    required this.status,
    required this.detail,
  });

  final String name;
  final DoctorStatus status;
  final String detail;

  factory DoctorCheck.fromJson(Map<String, Object?> json) {
    return DoctorCheck(
      name: _string(json['name']),
      status: DoctorStatus.parse(_string(json['status'])),
      detail: _string(json['detail']),
    );
  }
}

/// `restore --list-packs --json` 的一项。
class PackRef {
  const PackRef({
    required this.name,
    required this.path,
    required this.size,
    required this.present,
    required this.files,
    required this.bytes,
  });

  final String name;
  final String path;
  final int size;
  final bool present;
  final int files;
  final int bytes;

  factory PackRef.fromJson(Map<String, Object?> json) {
    return PackRef(
      name: _string(json['name']),
      path: _string(json['path']),
      size: _int(json['size']),
      present: _bool(json['present']),
      files: _int(json['files']),
      bytes: _int(json['bytes']),
    );
  }
}

/// `export-key --json`，敏感信息；不要 `toString`。
class ExportKeyInfo {
  const ExportKeyInfo({required this.armor, required this.grouped});

  final String armor;
  final String grouped;

  factory ExportKeyInfo.fromJson(Map<String, Object?> json) {
    return ExportKeyInfo(
      armor: _string(json['armor']),
      grouped: _string(json['grouped']),
    );
  }
}
