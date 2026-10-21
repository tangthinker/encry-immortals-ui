/// 解析 CLI 写到 stderr 的人类进度。只用于显示，不用于判断成功/失败/剩余量。
class CoreProgress {
  const CoreProgress({
    required this.phase,
    required this.doneFiles,
    required this.totalFiles,
    required this.doneText,
    required this.totalText,
    required this.percent,
    this.current,
    this.speedMibPerSecond,
    required this.raw,
  });

  /// backup / restore / unknown
  final String phase;
  final int doneFiles;
  final int totalFiles;
  final String doneText;
  final String totalText;
  final int percent;
  final String? current;
  final double? speedMibPerSecond;
  final String raw;

  bool get hasFiles => totalFiles > 0;
}

final RegExp _progressPattern = RegExp(
  r'^(备份|还原)进度 (\d+)/(\d+) 文件 · (.*?)（(\d+)%）(.*)$',
);
final RegExp _speedPattern = RegExp(r'([\d.]+) MiB/s');
final RegExp _currentPattern = RegExp(r'当前 (.*)$');

CoreProgress? parseCoreProgress(String line) {
  final match = _progressPattern.firstMatch(line.trim());
  if (match == null) return null;
  final phase = match.group(1) == '备份' ? 'backup' : 'restore';
  final doneFiles = int.tryParse(match.group(2) ?? '') ?? 0;
  final totalFiles = int.tryParse(match.group(3) ?? '') ?? 0;
  final bytes = (match.group(4) ?? '').split('/');
  final percent = (int.tryParse(match.group(5) ?? '') ?? 0).clamp(0, 100);
  final tail = match.group(6) ?? '';
  final speed = _speedPattern.firstMatch(tail);
  final current = _currentPattern.firstMatch(tail);
  return CoreProgress(
    phase: phase,
    doneFiles: doneFiles,
    totalFiles: totalFiles,
    doneText: bytes.isNotEmpty ? bytes.first.trim() : '',
    totalText: bytes.length > 1 ? bytes[1].trim() : '',
    percent: percent,
    current: current?.group(1)?.trim(),
    speedMibPerSecond: speed == null ? null : double.tryParse(speed.group(1)!),
    raw: line,
  );
}
