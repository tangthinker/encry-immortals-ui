import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core_command.dart';
import '../core/core_gateway.dart';
import '../core/core_locator.dart';
import '../core/core_models.dart';

class BootstrapInfo {
  const BootstrapInfo({
    this.binary,
    this.integrity,
    this.gateway,
    this.version,
    this.error,
    this.searchedPaths = const <String>[],
  });

  final CoreBinary? binary;
  final CoreIntegrityResult? integrity;
  final CoreGateway? gateway;
  final String? version;
  final String? error;
  final List<String> searchedPaths;

  bool get ready => gateway != null && binary != null;

  String get sourceLabel => switch (binary?.source) {
    CoreBinarySource.environmentOverride => '开发覆盖 · EIMMORTAL_CORE_PATH',
    CoreBinarySource.bundle => '随 App 打包',
    CoreBinarySource.development => '开发路径',
    null => '未知',
  };

  String get integrityLabel => switch (integrity?.status) {
    CoreIntegrityStatus.verified => 'SHA-256 已校验',
    CoreIntegrityStatus.notPinned => '开发构建 · 未固定哈希',
    CoreIntegrityStatus.mismatch => '哈希不匹配 · 已阻止执行',
    CoreIntegrityStatus.missing => 'sidecar 缺失',
    null => '未检查',
  };

  bool get integrityOk =>
      integrity?.status == CoreIntegrityStatus.verified ||
      integrity?.status == CoreIntegrityStatus.notPinned;
}

/// 启动时定位 sidecar、校验完整性并读取版本；失败不抛出，交给 UI 展示。
final bootstrapProvider = FutureProvider<BootstrapInfo>((ref) async {
  try {
    final locator = CoreLocator.current(allowEnvironmentOverride: kDebugMode);
    final binary = locator.locate();
    final integrity = await binary.verifyIntegrity();
    if (integrity.status == CoreIntegrityStatus.mismatch) {
      return BootstrapInfo(
        binary: binary,
        integrity: integrity,
        error: 'sidecar 的 SHA-256 与构建期记录不一致，已禁止执行。',
      );
    }

    final gateway = CoreGateway(binary: binary);
    final result = await gateway.run(
      const CoreRequest(
        command: CoreCommand.version,
        timeout: Duration(seconds: 15),
      ),
    );
    if (!result.isSuccess) {
      return BootstrapInfo(
        binary: binary,
        integrity: integrity,
        error: '无法读取核心版本：${result.errorSummary}',
      );
    }
    return BootstrapInfo(
      binary: binary,
      integrity: integrity,
      gateway: gateway,
      version: parseCoreVersion(result.stdout),
    );
  } on CoreBinaryNotFound catch (error) {
    return BootstrapInfo(
      error: error.message,
      searchedPaths: error.searchedPaths,
    );
  } catch (error) {
    return BootstrapInfo(error: '$error');
  }
});
