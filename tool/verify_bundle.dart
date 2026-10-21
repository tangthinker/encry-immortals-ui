import 'dart:io';

import 'package:encry_immortals_ui/core/core_command.dart';
import 'package:encry_immortals_ui/core/core_gateway.dart';
import 'package:encry_immortals_ui/core/core_locator.dart';
import 'package:encry_immortals_ui/core/core_models.dart';
import 'package:path/path.dart' as p;

/// 验证 macOS app bundle 里的 sidecar 路径、SHA-256 与版本：
///
/// ```bash
/// dart run tool/verify_bundle.dart \
///   "build/macos/Build/Products/Release/Encry Immortals.app" \
///   "$(cat build/core/eimmortal.sha256)"
/// ```
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法：dart run tool/verify_bundle.dart <app 路径> [期望 SHA-256]');
    exit(2);
  }
  final app = p.absolute(args[0]);
  final expected = args.length > 1 ? args[1] : null;
  final executable = p.join(app, 'Contents', 'MacOS', 'Encry Immortals');
  if (!File(executable).existsSync()) {
    stderr.writeln('找不到 app 可执行文件：$executable');
    exit(2);
  }

  final binary = CoreLocator(
    resolvedExecutable: executable,
    environment: const {},
    operatingSystem: 'macos',
    allowEnvironmentOverride: false,
    expectedSha256: expected,
  ).locate();
  final integrity = await binary.verifyIntegrity();
  final gateway = CoreGateway(binary: binary);
  final version = await gateway.run(
    const CoreRequest(
      command: CoreCommand.version,
      timeout: Duration(seconds: 15),
    ),
  );

  stdout.writeln('binary: ${binary.path}');
  stdout.writeln('source: ${binary.source.name}');
  stdout.writeln('integrity: ${integrity.status.name}');
  stdout.writeln('sha256: ${integrity.actualSha256}');
  stdout.writeln('version: ${parseCoreVersion(version.stdout)}');
  if (!integrity.isAcceptable || !version.isSuccess) exit(1);
}
