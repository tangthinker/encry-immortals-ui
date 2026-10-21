import 'dart:async';

import 'core_command.dart';
import 'core_gateway.dart';
import 'core_models.dart';
import 'core_result.dart';
import 'command_queue.dart';
import 'profile.dart';

class SessionLockedException implements Exception {
  const SessionLockedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 已解锁会话上的所有真实操作。密码只存在于本对象内存中，锁定时清空。
class VaultSession {
  VaultSession({
    required this.gateway,
    required this.profile,
    required this.queue,
  });

  final CoreGateway gateway;
  Profile profile;
  final CommandQueue queue;

  String? _password;

  bool get isUnlocked => _password != null;

  void updateProfile(Profile next) {
    profile = next;
  }

  String _requirePassword() {
    final password = _password;
    if (password == null) {
      throw const SessionLockedException('会话已锁定，请重新输入主密码。');
    }
    return password;
  }

  Future<CoreResult> _run({
    required CoreCommand command,
    List<String> args = const <String>[],
    String? password,
    String? armorKey,
    String? label,
    Duration? timeout,
    void Function(String line)? onStderr,
  }) {
    final effectivePassword = password ??
        (command.needsPasswordFor(args) ? _requirePassword() : null);
    return queue.run(label ?? command.label, (ticket) async {
      final run = gateway.start(
        CoreRequest(
          command: command,
          args: args,
          password: effectivePassword,
          armorKey: armorKey,
          configPath: profile.configPath,
          timeout: timeout,
        ),
      );
      ticket.attach(run.cancel);
      final subscription = onStderr == null
          ? null
          : run.stderrLines.listen(onStderr);
      try {
        return await run.result;
      } finally {
        await subscription?.cancel();
      }
    });
  }

  /// 用 `log` 作为解锁探针；成功才把密码留在内存。
  Future<CoreResult> unlock(String password) async {
    final result = await _run(
      command: CoreCommand.log,
      password: password,
      label: '解锁',
    );
    final ok = result.isSuccess && !result.protocolError && result.jsonList != null;
    if (ok) {
      _password = password;
    } else {
      _password = null;
    }
    return result;
  }

  /// 只验证密码，不改变当前会话（导出 Key 前的再认证）。
  Future<CoreResult> verifyPassword(String password) {
    return _run(
      command: CoreCommand.log,
      password: password,
      label: '验证主密码',
    );
  }

  void lock() {
    _password = null;
  }

  Future<CoreResult> status({
    bool chain = false,
    void Function(String line)? onStderr,
  }) {
    return _run(
      command: CoreCommand.status,
      args: chain ? const ['--chain'] : const [],
      onStderr: onStderr,
    );
  }

  Future<CoreResult> history({
    void Function(String line)? onStderr,
  }) {
    return _run(command: CoreCommand.log, onStderr: onStderr);
  }

  Future<CoreResult> show(int seq) {
    return _run(command: CoreCommand.show, args: ['$seq']);
  }

  Future<CoreResult> listSnapshot(int seq, {String prefix = ''}) {
    return _run(
      command: CoreCommand.ls,
      args: ['--at', '$seq', if (prefix.trim().isNotEmpty) prefix.trim()],
    );
  }

  Future<CoreResult> backup({
    bool dryRun = false,
    bool breakLock = false,
    String? message,
    void Function(String line)? onStderr,
  }) {
    final trimmed = message?.trim();
    return _run(
      command: CoreCommand.backup,
      args: [
        '--source',
        profile.sourceRoot,
        if (dryRun) '--dry-run',
        if (breakLock) '--break-lock',
        if (trimmed != null && trimmed.isNotEmpty) ...['-m', trimmed],
      ],
      onStderr: onStderr,
    );
  }

  Future<CoreResult> restore({
    required String destination,
    int? seq,
    String overwrite = 'never',
    bool dryRun = false,
    bool listPacks = false,
    bool skipMissingPacks = false,
    Duration? waitForPacks,
    void Function(String line)? onStderr,
  }) {
    final args = <String>[
      if (seq != null) ...['--at', '$seq'],
      if (overwrite != 'never') ...['--overwrite', overwrite],
      if (dryRun) '--dry-run',
      if (listPacks) '--list-packs',
      if (skipMissingPacks) '--skip-missing-packs',
      if (waitForPacks != null)
        ...['--wait-for-packs', '${waitForPacks.inSeconds}s'],
      if (!listPacks) destination,
    ];
    return _run(
      command: CoreCommand.restore,
      args: args,
      onStderr: onStderr,
    );
  }

  Future<CoreResult> verify({
    int? sample,
    bool deep = false,
    void Function(String line)? onStderr,
  }) {
    return _run(
      command: CoreCommand.verify,
      args: [
        if (sample != null) ...['--sample', '$sample'],
        if (deep) '--deep',
      ],
      onStderr: onStderr,
    );
  }

  Future<CoreResult> doctor({
    bool chain = true,
    void Function(String line)? onStderr,
  }) {
    return _run(
      command: CoreCommand.doctor,
      args: chain ? const ['--chain'] : const [],
      onStderr: onStderr,
    );
  }

  Future<CoreResult> exportKey() {
    if (!isUnlocked) {
      throw const SessionLockedException('会话已锁定，无法导出 Armor Key。');
    }
    return _run(command: CoreCommand.exportKey);
  }

  /// `status` 无密码也能拿控制锁；成功返回说明控制锁当前没有其他进程占用。
  Future<CoreResult> probeControlLock() {
    return _run(
      command: CoreCommand.status,
      label: '检查控制锁',
    );
  }
}

ExportKeyInfo? exportKeyFromResult(CoreResult result) {
  final json = result.jsonMap;
  if (json == null) return null;
  final info = ExportKeyInfo.fromJson(json);
  return info.armor.isEmpty ? null : info;
}
