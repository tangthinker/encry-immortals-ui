import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// 构建期注入的 sidecar SHA-256（由打包脚本写入 --dart-define）。
///
/// 开发构建为空字符串；release 构建为空应视为配置错误，在打包阶段强制校验。
const String buildTimeCoreSha256 = String.fromEnvironment('EIMMORTAL_CORE_SHA256');

enum CoreBinarySource {
  environmentOverride,
  bundle,
  development,
}

class CoreBinary {
  const CoreBinary({
    required this.path,
    required this.source,
    this.expectedSha256,
  });

  final String path;
  final CoreBinarySource source;
  final String? expectedSha256;

  bool get isBundled => source == CoreBinarySource.bundle;

  bool get isPinned => expectedSha256 != null && expectedSha256!.isNotEmpty;

  File get file => File(path);

  bool exists() => file.existsSync();

  Future<String> sha256Hex() async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<CoreIntegrityResult> verifyIntegrity() async {
    if (!exists()) {
      return const CoreIntegrityResult(
        status: CoreIntegrityStatus.missing,
        actualSha256: null,
        expectedSha256: null,
      );
    }
    if (!isPinned) {
      return CoreIntegrityResult(
        status: CoreIntegrityStatus.notPinned,
        actualSha256: await sha256Hex(),
        expectedSha256: null,
      );
    }
    final actual = await sha256Hex();
    return CoreIntegrityResult(
      status: actual.toLowerCase() == expectedSha256!.toLowerCase()
          ? CoreIntegrityStatus.verified
          : CoreIntegrityStatus.mismatch,
      actualSha256: actual,
      expectedSha256: expectedSha256,
    );
  }
}

enum CoreIntegrityStatus {
  verified,
  notPinned,
  mismatch,
  missing,
}

class CoreIntegrityResult {
  const CoreIntegrityResult({
    required this.status,
    required this.actualSha256,
    required this.expectedSha256,
  });

  final CoreIntegrityStatus status;
  final String? actualSha256;
  final String? expectedSha256;

  bool get isAcceptable =>
      status == CoreIntegrityStatus.verified ||
      status == CoreIntegrityStatus.notPinned;
}

class CoreBinaryNotFound implements Exception {
  const CoreBinaryNotFound(this.searchedPaths, this.message);

  final List<String> searchedPaths;
  final String message;

  @override
  String toString() => message;
}

/// 解析 sidecar 路径。
///
/// - 生产环境只允许 app bundle/安装目录内的固定路径；
/// - debug 构建允许 `EIMMORTAL_CORE_PATH` 覆盖，方便指向本地上游 `bin/eimmortal`。
class CoreLocator {
  const CoreLocator({
    required this.resolvedExecutable,
    required this.environment,
    required this.operatingSystem,
    this.allowEnvironmentOverride = false,
    this.expectedSha256,
  });

  factory CoreLocator.current({
    bool allowEnvironmentOverride = false,
    String? expectedSha256,
  }) {
    return CoreLocator(
      resolvedExecutable: Platform.resolvedExecutable,
      environment: Platform.environment,
      operatingSystem: Platform.operatingSystem,
      allowEnvironmentOverride: allowEnvironmentOverride,
      expectedSha256: expectedSha256 ?? buildTimeCoreSha256,
    );
  }

  final String resolvedExecutable;
  final Map<String, String> environment;
  final String operatingSystem;
  final bool allowEnvironmentOverride;
  final String? expectedSha256;

  CoreBinary locate() {
    final override = environment['EIMMORTAL_CORE_PATH']?.trim();
    if (allowEnvironmentOverride && override != null && override.isNotEmpty) {
      return _existingOrThrow(
        [override],
        source: CoreBinarySource.environmentOverride,
      );
    }

    final candidates = <String>[];
    if (operatingSystem == 'macos') {
      // <App>.app/Contents/MacOS/<executable>
      final contents = p.dirname(p.dirname(resolvedExecutable));
      candidates.add(p.join(contents, 'Resources', 'bin', 'eimmortal'));
      candidates.add(p.join(contents, 'MacOS', 'eimmortal'));
    } else if (operatingSystem == 'windows') {
      final installDir = p.dirname(resolvedExecutable);
      candidates.addAll([
        p.join(installDir, 'bin', 'eimmortal-gui.exe'),
        p.join(installDir, 'bin', 'eimmortal.exe'),
        p.join(installDir, 'eimmortal-gui.exe'),
        p.join(installDir, 'eimmortal.exe'),
      ]);
    }

    if (candidates.isEmpty) {
      throw CoreBinaryNotFound(
        const [],
        '当前平台 $operatingSystem 不受支持；客户端仅支持 macOS 与 Windows。',
      );
    }
    return _existingOrThrow(candidates, source: CoreBinarySource.bundle);
  }

  CoreBinary _existingOrThrow(
    List<String> candidates, {
    required CoreBinarySource source,
  }) {
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return CoreBinary(
          path: p.absolute(candidate),
          source: source,
          expectedSha256: expectedSha256,
        );
      }
    }
    throw CoreBinaryNotFound(
      candidates,
      '找不到核心 sidecar。已查找：${candidates.join('、')}'
      '${source == CoreBinarySource.bundle && allowEnvironmentOverride ? '。开发模式可用 EIMMORTAL_CORE_PATH 指定路径。' : ''}',
    );
  }
}
