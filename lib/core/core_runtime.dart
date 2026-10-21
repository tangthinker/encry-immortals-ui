import 'core_command.dart';
import 'core_gateway.dart';
import 'core_locator.dart';
import 'core_models.dart';
import 'core_process.dart';

class CoreRuntimeException implements Exception {
  const CoreRuntimeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CoreRuntime {
  const CoreRuntime({
    required this.binary,
    required this.integrity,
    required this.version,
    required this.gateway,
  });

  final CoreBinary binary;
  final CoreIntegrityResult integrity;
  final String version;
  final CoreGateway gateway;

  bool get integrityOk =>
      integrity.status == CoreIntegrityStatus.verified ||
      integrity.status == CoreIntegrityStatus.notPinned;

  static Future<CoreRuntime> load({
    bool allowEnvironmentOverride = false,
    String? expectedSha256,
    CoreProcessLauncher? launcher,
  }) async {
    final CoreBinary binary;
    try {
      binary = CoreLocator.current(
        allowEnvironmentOverride: allowEnvironmentOverride,
        expectedSha256: expectedSha256,
      ).locate();
    } on CoreBinaryNotFound catch (error) {
      throw CoreRuntimeException(error.message);
    }

    final integrity = await binary.verifyIntegrity();
    if (integrity.status == CoreIntegrityStatus.mismatch) {
      throw const CoreRuntimeException(
        'sidecar 的 SHA-256 与构建期记录不一致，已禁止执行。',
      );
    }
    if (integrity.status == CoreIntegrityStatus.missing) {
      throw CoreRuntimeException('sidecar 不存在：${binary.path}');
    }

    final gateway = launcher == null
        ? CoreGateway(binary: binary)
        : CoreGateway(binary: binary, launcher: launcher);
    final version = await gateway.run(
      const CoreRequest(
        command: CoreCommand.version,
        timeout: Duration(seconds: 15),
      ),
    );
    if (!version.isSuccess) {
      throw CoreRuntimeException('无法读取核心版本：${version.errorSummary}');
    }
    return CoreRuntime(
      binary: binary,
      integrity: integrity,
      version: parseCoreVersion(version.stdout),
      gateway: gateway,
    );
  }
}
