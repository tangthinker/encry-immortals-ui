import 'core_command.dart';
import 'core_exit_code.dart';

/// 一次核心 CLI 调用的结果。
///
/// 注意：`stdout` / `stderr` 可能是敏感内容（init / export-key / import-key）。
/// 不要把 [CoreResult] 直接交给通用日志器；使用 [safeSummary] 或 [redacted]。
class CoreResult {
  const CoreResult({
    required this.command,
    required this.arguments,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.json,
    required this.jsonParsed,
    required this.duration,
    required this.startedAt,
    this.cancelled = false,
    this.timedOut = false,
    this.protocolError = false,
    this.stdoutTruncated = false,
  });

  final CoreCommand command;

  /// 实际传给进程的参数（不含密码；含配置路径）。
  final List<String> arguments;

  final int exitCode;
  final String stdout;
  final String stderr;

  /// 成功解析的 JSON（可能是 List / Map / null 值的 JSON）。
  final Object? json;

  /// stdout 是否是可解析的 JSON。空 stdout 为 false。
  final bool jsonParsed;

  final Duration duration;
  final DateTime startedAt;

  /// 用户主动取消，或子进程以取消信号退出。
  final bool cancelled;

  /// 是否因网关超时被终止。
  final bool timedOut;

  /// 退出码为 0、但期望 JSON 却没解析出来（协议漂移）。
  final bool protocolError;

  /// stdout 超过网关上限，只保留了前一部分。
  final bool stdoutTruncated;

  CoreExitCode get exit => CoreExitCode.fromCode(exitCode);
  bool get isSuccess => exitCode == 0;
  bool get isFailure => !isSuccess;
  bool get sensitive => command.sensitive;

  Map<String, Object?>? get jsonMap {
    final value = json;
    if (value is Map<String, Object?>) return value;
    if (value is Map) return value.cast<String, Object?>();
    return null;
  }

  List<Object?>? get jsonList {
    final value = json;
    if (value is List) return value.cast<Object?>();
    return null;
  }

  /// 适合展示/写日志的最后一条错误信息。
  String get errorSummary {
    final lines = stderr
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return exit.label;
    return lines.last;
  }

  /// 摘要永远不包含敏感命令的 stdout（Armor Key）。
  String get safeSummary {
    final buffer = StringBuffer('${command.name} exit=$exitCode in ${duration.inMilliseconds}ms');
    if (cancelled) buffer.write(' cancelled');
    if (timedOut) buffer.write(' timedOut');
    if (protocolError) buffer.write(' protocolError');
    if (!isSuccess) buffer.write(' · $errorSummary');
    return buffer.toString();
  }

  /// 返回可安全用于日志的副本：敏感命令清空 stdout/stderr。
  CoreResult redacted() {
    if (!sensitive) return this;
    return CoreResult(
      command: command,
      arguments: arguments,
      exitCode: exitCode,
      stdout: '<redacted:${stdout.length} bytes>',
      stderr: '<redacted:${stderr.length} bytes>',
      json: null,
      jsonParsed: false,
      duration: duration,
      startedAt: startedAt,
      cancelled: cancelled,
      timedOut: timedOut,
      protocolError: protocolError,
      stdoutTruncated: stdoutTruncated,
    );
  }

  @override
  String toString() => 'CoreResult($safeSummary)';
}
