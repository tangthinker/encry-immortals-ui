import 'package:encry_immortals_ui/core/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析未解锁的 status（referenced=0 不是真实数据）', () {
    final status = VaultStatus.fromJson({
      'schema': 1,
      'vault_id': 'abc',
      'last_seq': 3,
      'anchor_short': 'D74B-4144',
      'verified': true,
      'packs': {
        'local': 2,
        'referenced': 0,
        'orphan': 0,
        'missing': 0,
      },
      'bytes': {
        'pack_total': 10,
        'journal_total': 2,
        'staging': 0,
        'logical_source': 0,
      },
      'tmp_entries': 0,
      'warnings': ['从未做过恢复演练'],
    });

    expect(status.schema, 1);
    expect(status.lastSeq, 3);
    expect(status.hasUnlockWarning, isFalse);
    expect(status.isUnlockedView, isFalse);
    expect(status.isHealthy, isTrue);
  });

  test('密码错误时 status --chain 的 warning 必须被识别', () {
    final status = VaultStatus.fromJson({
      'schema': 1,
      'verified': true,
      'packs': {'local': 1, 'referenced': 0, 'orphan': 0, 'missing': 0},
      'bytes': {'logical_source': 0},
      'warnings': ['从未做过恢复演练', '主密码无法解锁 vault，链统计未计算'],
    });

    expect(status.hasUnlockWarning, isTrue);
    expect(status.isHealthy, isFalse);
  });

  test('空提交历史与 null 数组不崩溃', () {
    expect(parseCoreVersion('eimmortal 0.1.0-dev\n'), '0.1.0-dev');

    final restore = RestoreSummary.fromJson({
      'seq': 1,
      'files': 2,
      'dirs': 1,
      'links': 0,
      'bytes': 100,
      'skipped': null,
      'corrupt': null,
      'missing_packs': null,
      'missing_files': null,
      'incomplete': false,
      'dry_run': false,
    });
    expect(restore.missingPacks, isNull);
    expect(restore.incomplete, isFalse);

    final verify = VerifySummary.fromJson({
      'local_packs': 1,
      'referenced_packs': 1,
      'missing': null,
      'size_mismatch': null,
      'orphans': 0,
      'sampled': 1,
      'sample_failures': null,
      'deep_files': 0,
      'deep_bytes': 0,
      'deep_failures': null,
    });
    expect(verify.isClean, isTrue);
  });

  test('未知字段与缺失字段保持默认值', () {
    final entry = CommitEntry.fromJson({
      'seq': 2,
      'ts_unix': 1700000000,
      'unknown_future_field': {'nested': true},
    });
    expect(entry.seq, 2);
    expect(entry.message, isEmpty);
    expect(entry.timestamp.year, greaterThan(2000));
  });

  test('doctor 状态解析', () {
    final checks = [
      DoctorCheck.fromJson({'name': 'a', 'status': 'PASS', 'detail': ''}),
      DoctorCheck.fromJson({'name': 'b', 'status': 'WARN', 'detail': ''}),
      DoctorCheck.fromJson({'name': 'c', 'status': 'FAIL', 'detail': ''}),
      DoctorCheck.fromJson({'name': 'd', 'status': 'SKIP', 'detail': ''}),
      DoctorCheck.fromJson({'name': 'e', 'status': 'FUTURE', 'detail': ''}),
    ];
    expect(checks.map((check) => check.status.label), [
      'PASS',
      'WARN',
      'FAIL',
      'SKIP',
      '未知',
    ]);
    expect(checks.where((check) => check.status.isBlocking), hasLength(1));
  });
}
