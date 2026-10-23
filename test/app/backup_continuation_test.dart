import 'package:encry_immortals_ui/app/backup_continuation.dart';
import 'package:encry_immortals_ui/core/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

BackupSummary summary({
  int seq = 3,
  bool changed = true,
  int added = 1,
  int modified = 0,
  int deleted = 0,
  int dirs = 0,
  int meta = 0,
  int links = 0,
  int plainBytes = 1024,
  bool truncated = true,
}) {
  return BackupSummary(
    seq: seq,
    changed: changed,
    dryRun: false,
    added: added,
    modified: modified,
    deleted: deleted,
    meta: meta,
    dirs: dirs,
    links: links,
    plainBytes: plainBytes,
    packBytes: 512,
    journalBytes: 128,
    manifests: 1,
    truncated: truncated,
    skipped: 0,
  );
}

void main() {
  group('backupHasProgress', () {
    test('新 seq 且有新增文件时允许继续', () {
      expect(backupHasProgress(summary(), previousSeq: 2), isTrue);
    });

    test('seq 未推进时停止，避免无限循环', () {
      expect(backupHasProgress(summary(seq: 3), previousSeq: 3), isFalse);
    });

    test('没有 changed 时不继续', () {
      expect(backupHasProgress(summary(changed: false)), isFalse);
    });

    test('changed=true 但没有任何条目或明文体积时停止', () {
      expect(backupHasProgress(summary(added: 0, plainBytes: 0)), isFalse);
    });

    test('只有删除/目录/元数据变化也算推进', () {
      expect(
        backupHasProgress(summary(added: 0, deleted: 2, plainBytes: 0)),
        isTrue,
      );
      expect(
        backupHasProgress(summary(added: 0, dirs: 1, plainBytes: 0)),
        isTrue,
      );
      expect(
        backupHasProgress(summary(added: 0, meta: 1, plainBytes: 0)),
        isTrue,
      );
    });

    test('seq 0 不算推进', () {
      expect(backupHasProgress(summary(seq: 0)), isFalse);
    });
  });
}
