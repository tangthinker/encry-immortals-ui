import 'dart:io';

import 'package:path/path.dart' as p;

import 'vault_settings.dart';

enum ProfileMode {
  created,
  joined;

  String get label => this == ProfileMode.created ? '新建库' : '加入已有库';

  static ProfileMode parse(String value) {
    return value == 'joined' ? ProfileMode.joined : ProfileMode.created;
  }
}

class ProfileFormatException implements Exception {
  const ProfileFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// GUI 的单一 profile。源根目录在这里固定下来：同一个 TargetDir 不允许换源根。
class Profile {
  Profile({
    required this.id,
    required this.name,
    required this.vaultDir,
    required this.targetDir,
    required this.configPath,
    required this.sourceRoot,
    required this.mode,
    required this.createdAt,
    VaultSettings? settings,
    int? sessionMaxMib,
    bool? ignoreXattr,
    this.schema = currentSchema,
  }) : settings = (settings ?? const VaultSettings()).copyWith(
         sessionMaxMib: sessionMaxMib,
         ignoreXattr: ignoreXattr,
       );

  static const int currentSchema = 1;

  final int schema;
  final String id;
  final String name;
  final String vaultDir;
  final String targetDir;
  final String configPath;
  final String sourceRoot;
  final ProfileMode mode;
  final DateTime createdAt;
  final VaultSettings settings;

  int get sessionMaxMib => settings.sessionMaxMib;
  bool get ignoreXattr => settings.ignoreXattr;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'id': id,
    'name': name,
    'vault_dir': vaultDir,
    'target_dir': targetDir,
    'config_path': configPath,
    'source_root': sourceRoot,
    'mode': mode.name,
    'created_at': createdAt.toUtc().toIso8601String(),
    // 新格式；同时写 legacy 字段，便于旧版本/手工排查。
    'settings': settings.toJson(),
    'session_max_mib': settings.sessionMaxMib,
    'ignore_xattr': settings.ignoreXattr,
  };

  factory Profile.fromJson(Map<String, Object?> json) {
    if (json['schema'] != currentSchema) {
      throw ProfileFormatException(
        'profile.json 的 schema=${json['schema']} 不受支持（需要 $currentSchema）。',
      );
    }
    String required(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw ProfileFormatException('profile.json 缺少字段：$key');
      }
      return value;
    }

    final targetDir = required('target_dir');
    final sourceRoot = required('source_root');
    final vaultDir = required('vault_dir');
    final configPath = required('config_path');
    for (final entry in {
      'target_dir': targetDir,
      'source_root': sourceRoot,
      'vault_dir': vaultDir,
      'config_path': configPath,
    }.entries) {
      if (!p.isAbsolute(entry.value)) {
        throw ProfileFormatException(
          'profile.json 的 ${entry.key} 不是绝对路径：${entry.value}',
        );
      }
    }

    final createdRaw = required('created_at');
    final createdAt = DateTime.tryParse(createdRaw);
    if (createdAt == null) {
      throw ProfileFormatException('profile.json 的 created_at 非法：$createdRaw');
    }

    final rawSettings = json['settings'];
    final settings = rawSettings is Map
        ? VaultSettings.fromJson(
            rawSettings.map((key, value) => MapEntry('$key', value)),
          )
        : VaultSettings.fromJson(json);
    final settingsError = settings.validate();
    if (settingsError != null) {
      throw ProfileFormatException('profile.json 参数非法：$settingsError');
    }
    return Profile(
      schema: currentSchema,
      id: required('id'),
      name: required('name'),
      vaultDir: vaultDir,
      targetDir: targetDir,
      configPath: configPath,
      sourceRoot: sourceRoot,
      mode: ProfileMode.parse(json['mode'] as String? ?? 'created'),
      createdAt: createdAt,
      settings: settings,
    );
  }

  Profile copyWith({
    String? name,
    String? vaultDir,
    String? targetDir,
    String? configPath,
    String? sourceRoot,
    ProfileMode? mode,
    DateTime? createdAt,
    VaultSettings? settings,
    int? sessionMaxMib,
    bool? ignoreXattr,
  }) {
    final nextSettings = (settings ?? this.settings).copyWith(
      sessionMaxMib: sessionMaxMib,
      ignoreXattr: ignoreXattr,
    );
    return Profile(
      schema: schema,
      id: id,
      name: name ?? this.name,
      vaultDir: vaultDir ?? this.vaultDir,
      targetDir: targetDir ?? this.targetDir,
      configPath: configPath ?? this.configPath,
      sourceRoot: sourceRoot ?? this.sourceRoot,
      mode: mode ?? this.mode,
      createdAt: createdAt ?? this.createdAt,
      settings: nextSettings,
    );
  }

  bool get targetExists => Directory(targetDir).existsSync();
  bool get sourceExists => Directory(sourceRoot).existsSync();
  bool get vaultInitialized =>
      File(p.join(vaultDir, 'vault.meta')).existsSync();
}
