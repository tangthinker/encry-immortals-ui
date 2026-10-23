import '../core/core_models.dart';

/// Hard stop for the "keep backing up until complete" loop. A single file
/// larger than session_max_mib can otherwise keep the sidecar spinning
/// without producing a new commit.
const int maxContinuousBackupCommits = 1000;

/// Whether a truncated round actually moved data forward.
///
/// The sidecar can legitimately return `truncated=true` with no new commit
/// when a single object cannot fit into one session. The UI must stop instead
/// of retrying that state forever.
bool backupHasProgress(BackupSummary summary, {int? previousSeq}) {
  if (!summary.changed || summary.seq <= 0) return false;
  if (previousSeq != null && summary.seq == previousSeq) return false;
  final changedEntries =
      summary.added +
      summary.modified +
      summary.deleted +
      summary.meta +
      summary.dirs +
      summary.links;
  return changedEntries > 0 || summary.plainBytes > 0;
}
