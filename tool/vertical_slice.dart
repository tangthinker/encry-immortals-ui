import 'dart:io';

import 'package:encry_immortals_ui/core/core_gateway.dart';
import 'package:encry_immortals_ui/core/core_locator.dart';
import 'package:encry_immortals_ui/core/vertical_slice.dart';

/// 在终端里跑 M0 垂直切片：
///
/// ```bash
/// dart run tool/vertical_slice.dart /path/to/eimmortal
/// # 或
/// EIMMORTAL_CORE_PATH=/path/to/eimmortal dart run tool/vertical_slice.dart
/// ```
Future<void> main(List<String> args) async {
  final path = args.isNotEmpty
      ? args.first
      : Platform.environment['EIMMORTAL_CORE_PATH'];
  if (path == null || path.trim().isEmpty) {
    stderr.writeln(
      '用法：dart run tool/vertical_slice.dart <eimmortal 可执行文件>\n'
      '或设置 EIMMORTAL_CORE_PATH。',
    );
    exit(2);
  }

  final binary = CoreBinary(
    path: path,
    source: CoreBinarySource.environmentOverride,
    expectedSha256: Platform.environment['EIMMORTAL_CORE_SHA256'],
  );
  final gateway = CoreGateway(binary: binary);
  final runner = VerticalSliceRunner(
    gateway: gateway,
    logger: (message) => stdout.writeln(message),
  );

  stdout.writeln('eiMMORTAL M0 vertical slice');
  stdout.writeln('core: ${binary.path}');
  final report = await runner.run();
  stdout.writeln();
  for (final step in report.steps) {
    stdout.writeln(
      '${step.ok ? 'PASS' : 'FAIL'}  ${step.title.padRight(28)} '
      '${step.duration.inMilliseconds.toString().padLeft(5)} ms  ${step.detail}',
    );
  }
  stdout.writeln();
  stdout.writeln(
    '${report.success ? 'SLICE PASS' : 'SLICE FAIL'} · '
    '${report.passed}/${report.steps.length} steps · '
    '${report.duration.inMilliseconds} ms',
  );
  if (report.workDir != null) {
    stdout.writeln('现场保留：${report.workDir}');
  }
  if (report.error != null) {
    stdout.writeln('错误：${report.error}');
  }
  exit(report.success ? 0 : 1);
}
