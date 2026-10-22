import 'package:encry_immortals_ui/core/profile.dart';
import 'package:encry_immortals_ui/core/vault_settings.dart';
import 'package:flutter_test/flutter_test.dart';

Profile _profile() {
  return Profile(
    id: 'abc',
    name: 'docs',
    vaultDir: '/Users/a/Library/Application Support/EncryImmortals/vault',
    targetDir: '/Volumes/Backup/eimmortal',
    configPath:
        '/Users/a/Library/Application Support/EncryImmortals/config.toml',
    sourceRoot: '/Users/a/Documents',
    mode: ProfileMode.created,
    createdAt: DateTime.utc(2026, 10, 21, 12),
    sessionMaxMib: 512,
    ignoreXattr: true,
  );
}

void main() {
  test('profile JSON 往返', () {
    final profile = _profile();
    final decoded = Profile.fromJson(profile.toJson());
    expect(decoded.id, profile.id);
    expect(decoded.name, 'docs');
    expect(decoded.targetDir, profile.targetDir);
    expect(decoded.sourceRoot, profile.sourceRoot);
    expect(decoded.mode, ProfileMode.created);
    expect(decoded.sessionMaxMib, 512);
    expect(decoded.ignoreXattr, isTrue);
    expect(decoded.createdAt, profile.createdAt);
  });

  test('schema 不支持时拒绝加载', () {
    final json = _profile().toJson()..['schema'] = 2;
    expect(
      () => Profile.fromJson(json),
      throwsA(isA<ProfileFormatException>()),
    );
  });

  test('相对路径时拒绝加载', () {
    final json = _profile().toJson()..['target_dir'] = 'relative/path';
    expect(
      () => Profile.fromJson(json),
      throwsA(isA<ProfileFormatException>()),
    );
  });

  test('copyWith 只修改目标字段', () {
    final profile = _profile();
    final updated = profile.copyWith(sessionMaxMib: 1024, name: 'new');
    expect(updated.id, profile.id);
    expect(updated.sessionMaxMib, 1024);
    expect(updated.name, 'new');
    expect(updated.targetDir, profile.targetDir);
  });

  test('完整参数往返', () {
    final profile = _profile();
    final updated = profile.copyWith(
      settings: const VaultSettings(
        packMaxMiB: 256,
        slicePlainMiB: 16,
        smallFileMiB: 100,
        zstdLevel: 9,
        scanMode: 'strict',
        excludeRules: ['*.tmp'],
        ignoreXattr: false,
        stagingDir: '/tmp/stage',
      ),
    );
    final decoded = Profile.fromJson(updated.toJson());
    expect(decoded.settings, updated.settings);
    expect(decoded.settings.packMaxMiB, 256);
    expect(decoded.ignoreXattr, isFalse);
  });

  test('旧版扁平 profile 自动迁移到 settings', () {
    final json = _profile().toJson()..remove('settings');
    final decoded = Profile.fromJson(json);
    expect(decoded.sessionMaxMib, 512);
    expect(decoded.ignoreXattr, isTrue);
    expect(decoded.settings.packMaxMiB, 128);
  });

  test('mode 解析未知值回退为 created', () {
    expect(ProfileMode.parse('joined'), ProfileMode.joined);
    expect(ProfileMode.parse('unknown'), ProfileMode.created);
  });
}
