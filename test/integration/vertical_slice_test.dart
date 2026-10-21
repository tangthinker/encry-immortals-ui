@Tags(['integration'])
library;

import 'dart:io';

import 'package:encry_immortals_ui/core/core_gateway.dart';
import 'package:encry_immortals_ui/core/core_locator.dart';
import 'package:encry_immortals_ui/core/vertical_slice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final corePath = Platform.environment['EIMMORTAL_CORE_PATH'];
  final enabled =
      Platform.environment['RUN_CORE_INTEGRATION'] == '1' &&
      corePath != null &&
      corePath.isNotEmpty;

  test(
    'M0 垂直切片：init → backup → log → restore → verify → doctor',
    () async {
      final binary = CoreBinary(
        path: corePath!,
        source: CoreBinarySource.environmentOverride,
      );
      final gateway = CoreGateway(binary: binary);
      final logs = <String>[];
      final runner = VerticalSliceRunner(
        gateway: gateway,
        logger: logs.add,
      );

      final report = await runner.run();
      for (final step in report.steps) {
        // ignore: avoid_print
        print(
          '${step.ok ? 'PASS' : 'FAIL'} ${step.title} · ${step.detail}',
        );
      }
      expect(
        report.success,
        isTrue,
        reason: '切片失败：${report.error}\n${logs.join('\n')}',
      );
      expect(report.passed, report.steps.length);
      expect(report.steps, isNotEmpty);
      expect(report.workDir, isNull);
    },
    skip: enabled ? false : '需要 RUN_CORE_INTEGRATION=1 与 EIMMORTAL_CORE_PATH',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
