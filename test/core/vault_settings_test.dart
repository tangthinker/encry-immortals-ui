import 'package:encry_immortals_ui/core/vault_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('默认值与越界校验', () {
    const defaults = VaultSettings();
    expect(defaults.packMaxBytes, 128 * 1024 * 1024);
    expect(defaults.slicePlainBytes, 32 * 1024 * 1024);
    expect(defaults.smallFileBytes, 64 * 1024 * 1024);
    expect(defaults.sessionMaxMib, 1024);
    expect(defaults.zstdLevel, 5);
    expect(defaults.ignoreXattr, isTrue);
    expect(defaults.validate(), isNull);

    expect(const VaultSettings(zstdLevel: 0).validate(), isNotNull);
    expect(const VaultSettings(zstdLevel: 23).validate(), isNotNull);
    expect(const VaultSettings(slicePlainMiB: 65).validate(), isNotNull);
    expect(const VaultSettings(sessionMaxMib: 0).validate(), isNotNull);
    expect(const VaultSettings(scanMode: 'slow').validate(), isNotNull);
    expect(const VaultSettings(followHardlinks: 'copy').validate(), isNotNull);
    expect(
      const VaultSettings(onChangeStrategy: 'ignore').validate(),
      isNotNull,
    );
    expect(
      const VaultSettings(stagingDir: 'relative/dir').validate(),
      isNotNull,
    );
    expect(const VaultSettings(minCompressKiB: 1025).validate(), isNotNull);
    expect(const VaultSettings(sparseMaxMiB: -1).validate(), isNotNull);
  });

  test('跨字段约束：slice/small 必须塞进 pack', () {
    expect(
      const VaultSettings(packMaxMiB: 8, slicePlainMiB: 16).validate(),
      isNotNull,
    );
    expect(
      const VaultSettings(packMaxMiB: 8, smallFileMiB: 16).validate(),
      isNotNull,
    );
    expect(
      const VaultSettings(packMaxMiB: 32, slicePlainMiB: 32).validate(),
      isNotNull,
    );
  });

  test('JSON 往返保留全部参数', () {
    const settings = VaultSettings(
      packMaxMiB: 256,
      slicePlainMiB: 16,
      smallFileMiB: 100,
      sessionMaxMib: 512,
      zstdLevel: 9,
      minCompressKiB: 8,
      scanMode: 'strict',
      excludeRules: ['*.tmp'],
      followHardlinks: 'split',
      ignoreXattr: false,
      sparseMaxMiB: 2,
      onChangeStrategy: 'fail',
      stagingDir: '/tmp/stage',
    );
    final decoded = VaultSettings.fromJson(settings.toJson());
    expect(decoded, settings);
    expect(decoded.stagingDir, '/tmp/stage');
  });

  test('legacy 扁平字段可读', () {
    final decoded = VaultSettings.fromJson({
      'session_max_mib': 512,
      'ignore_xattr': false,
    });
    expect(decoded.sessionMaxMib, 512);
    expect(decoded.ignoreXattr, isFalse);
  });
}
