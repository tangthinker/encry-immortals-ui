import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'core_command.dart';
import 'core_gateway.dart';
import 'core_models.dart';
import 'core_result.dart';
import 'vault_config.dart';

typedef SliceLogger = void Function(String message);

class SliceStep {
  const SliceStep({
    required this.title,
    required this.ok,
    required this.detail,
    required this.duration,
    this.exitCode,
  });

  final String title;
  final bool ok;
  final String detail;
  final Duration duration;
  final int? exitCode;
}

class VerticalSliceReport {
  const VerticalSliceReport({
    required this.success,
    required this.steps,
    required this.duration,
    this.workDir,
    this.coreVersion,
    this.error,
    this.cancelled = false,
  });

  final bool success;
  final bool cancelled;
  final List<SliceStep> steps;
  final Duration duration;

  /// 失败且保留现场时的临时目录；成功时通常为 null。
  final String? workDir;
  final String? coreVersion;
  final String? error;

  int get passed => steps.where((step) => step.ok).length;
}

/// M0 垂直切片：init → backup → log → restore → verify → doctor。
///
/// 只使用临时目录与随机测试密码；Armor Key / 密码不会出现在日志或报告中。
/// 这条链路同时验证 sidecar 定位、stdin 密码、JSON 解析、退出码映射与单飞顺序。
class VerticalSliceRunner {
  VerticalSliceRunner({
    required this.gateway,
    this.logger,
    this.onStepStarted,
    this.onStepFinished,
    this.keepWorkDirOnFailure = true,
  });

  final CoreGateway gateway;
  final SliceLogger? logger;
  final void Function(String title)? onStepStarted;
  final void Function(SliceStep step)? onStepFinished;
  final bool keepWorkDirOnFailure;

  Future<void> Function()? _activeCancel;
  bool _cancelRequested = false;

  /// 取消当前命令；已排队/未开始的步骤会因上一步退出码 130 而终止。
  Future<void> cancel() async {
    _cancelRequested = true;
    await _activeCancel?.call();
  }

  static const int _fileCount = 3;
  static const int _randomFileBytes = 1024 * 1024;

  Future<VerticalSliceReport> run() async {
    final total = Stopwatch()..start();
    final steps = <SliceStep>[];
    Directory? workDir;
    String? error;
    String? coreVersion;

    void log(String message) => logger?.call(message);

    Future<CoreResult?> step({
      required String title,
      required CoreCommand command,
      List<String> args = const <String>[],
      bool withConfig = true,
      bool withPassword = false,
      String? passwordValue,
      bool Function(CoreResult)? accept,
      String Function(CoreResult)? detail,
    }) async {
      final stopwatch = Stopwatch()..start();
      log('▶ $title');
      onStepStarted?.call(title);
      CoreResult result;
      try {
        final run = gateway.start(
          CoreRequest(
            command: command,
            args: args,
            password: withPassword ? (passwordValue ?? '') : null,
            configPath: withConfig ? p.join(workDir!.path, 'config.toml') : null,
          ),
        );
        _activeCancel = run.cancel;
        try {
          result = await run.result;
        } finally {
          _activeCancel = null;
        }
      } on CoreLaunchException catch (launchError) {
        stopwatch.stop();
        final failedStep = SliceStep(
          title: title,
          ok: false,
          detail: launchError.message,
          duration: stopwatch.elapsed,
        );
        steps.add(failedStep);
        onStepFinished?.call(failedStep);
        log('✗ $title · ${launchError.message}');
        return null;
      }

      final ok = accept?.call(result) ?? result.isSuccess;
      stopwatch.stop();
      final stepDetail = detail?.call(result) ?? result.safeSummary;
      final finishedStep = SliceStep(
        title: title,
        ok: ok,
        detail: stepDetail,
        duration: stopwatch.elapsed,
        exitCode: result.exitCode,
      );
      steps.add(finishedStep);
      onStepFinished?.call(finishedStep);
      log('${ok ? '✓' : '✗'} $title · $stepDetail');
      return ok ? result : null;
    }

    try {
      workDir = await Directory.systemTemp.createTemp('eimmortal_slice_');
      final sourceDir = Directory(p.join(workDir.path, 'source'));
      final restoreDir = Directory(p.join(workDir.path, 'restored'));
      await sourceDir.create(recursive: true);
      await Directory(p.join(sourceDir.path, 'sub')).create(recursive: true);

      final password = _randomPassword();
      await _writeFixtureFiles(sourceDir);

      final config = VaultConfig(
        vaultDir: p.join(workDir.path, 'vault'),
        targetDir: p.join(workDir.path, 'target'),
        stagingDir: p.join(workDir.path, 'staging'),
        ignoreXattr: true,
        sessionMaxMib: 1024,
      );
      await config.writeTo(p.join(workDir.path, 'config.toml'));

      final version = await step(
        title: '读取核心版本',
        command: CoreCommand.version,
        withConfig: false,
        accept: (result) => result.isSuccess && result.stdout.trim().isNotEmpty,
        detail: (result) {
          coreVersion = parseCoreVersion(result.stdout);
          return 'core $coreVersion';
        },
      );
      if (version == null) return _finish(false, steps, total, workDir, coreVersion, error, log);

      final init = await step(
        title: '创建临时库（stdin 密码）',
        command: CoreCommand.init,
        withPassword: true,
        passwordValue: password,
        accept: (result) =>
            result.isSuccess &&
            File(p.join(workDir!.path, 'vault', 'vault.meta')).existsSync(),
        detail: (_) => 'vault.meta 已创建；Armor Key 仅保留在内存',
      );
      if (init == null) return _finish(false, steps, total, workDir, coreVersion, error, log);

      final key = await step(
        title: '导出 Armor Key（脱敏）',
        command: CoreCommand.exportKey,
        accept: (result) {
          final info = result.jsonMap == null
              ? null
              : ExportKeyInfo.fromJson(result.jsonMap!);
          return result.isSuccess && info != null && info.armor.isNotEmpty;
        },
        detail: (_) => 'armor 可解析；内容不写日志',
      );
      if (key == null) return _finish(false, steps, total, workDir, coreVersion, error, log);

      final emptyLog = await step(
        title: '读取空历史',
        command: CoreCommand.log,
        withPassword: true,
        passwordValue: password,
        accept: (result) => result.isSuccess && result.jsonList != null && result.jsonList!.isEmpty,
        detail: (result) => 'log 为空数组（${result.duration.inMilliseconds} ms）',
      );
      if (emptyLog == null) return _finish(false, steps, total, workDir, coreVersion, error, log);

      final backup = await step(
        title: '备份 3 个文件',
        command: CoreCommand.backup,
        args: ['--source', sourceDir.path, '-m', 'M0 vertical slice'],
        withPassword: true,
        passwordValue: password,
        accept: (result) {
          final summary = result.jsonMap == null
              ? null
              : BackupSummary.fromJson(result.jsonMap!);
          return result.isSuccess &&
              summary != null &&
              summary.changed &&
              summary.seq >= 1 &&
              summary.added == _fileCount;
        },
        detail: (result) {
          final summary = BackupSummary.fromJson(result.jsonMap ?? const {});
          return 'seq=${summary.seq} added=${summary.added} '
              'pack=${summary.packBytes} B';
        },
      );
      if (backup == null) return _finish(false, steps, total, workDir, coreVersion, error, log);
      final backupSeq = BackupSummary.fromJson(backup.jsonMap!).seq;

      final history = await step(
        title: '读取提交历史',
        command: CoreCommand.log,
        withPassword: true,
        passwordValue: password,
        accept: (result) {
          final entries = result.jsonList
              ?.map((item) => CommitEntry.fromJson(asJsonMap(item)))
              .toList();
          return result.isSuccess &&
              entries != null &&
              entries.any((entry) => entry.seq == backupSeq);
        },
        detail: (result) => '发现 seq=$backupSeq 的提交',
      );
      if (history == null) return _finish(false, steps, total, workDir, coreVersion, error, log);

      final status = await step(
        title: '读取库状态（无需密码）',
        command: CoreCommand.status,
        accept: (result) {
          final value = result.jsonMap == null
              ? null
              : VaultStatus.fromJson(result.jsonMap!);
          return result.isSuccess &&
              value != null &&
              value.schema == 1 &&
              value.lastSeq >= backupSeq;
        },
        detail: (result) {
          final value = VaultStatus.fromJson(result.jsonMap ?? const {});
          return 'schema=${value.schema} last_seq=${value.lastSeq} '
              'referenced=${value.referencedPacks}（未解锁，属预期）';
        },
      );
      if (status == null) return _finish(false, steps, total, workDir, coreVersion, error, log);

      final chain = await step(
        title: '链统计与锚点校验',
        command: CoreCommand.status,
        args: ['--chain'],
        withPassword: true,
        passwordValue: password,
        accept: (result) {
          final value = result.jsonMap == null
              ? null
              : VaultStatus.fromJson(result.jsonMap!);
          return result.isSuccess &&
              value != null &&
              !value.hasUnlockWarning &&
              value.referencedPacks >= 1;
        },
        detail: (result) {
          final value = VaultStatus.fromJson(result.jsonMap ?? const {});
          return 'referenced=${value.referencedPacks} '
              'missing=${value.missingPacks} verified=${value.verified}';
        },
      );
      if (chain == null) return _finish(false, steps, total, workDir, coreVersion, error, log);

      final wrongPassword = await step(
        title: '错误密码探针',
        command: CoreCommand.log,
        withPassword: true,
        passwordValue: 'wrong-${_randomPassword()}',
        accept: (result) => result.exitCode == 10 && result.stdout.trim().isEmpty,
        detail: (result) => 'exit=${result.exitCode}，stdout 为空；符合契约',
      );
      if (wrongPassword == null) {
        return _finish(false, steps, total, workDir, coreVersion, error, log);
      }

      await restoreDir.create(recursive: true);
      final restore = await step(
        title: '恢复到临时目录',
        command: CoreCommand.restore,
        args: [restoreDir.path],
        withPassword: true,
        passwordValue: password,
        accept: (result) {
          final summary = result.jsonMap == null
              ? null
              : RestoreSummary.fromJson(result.jsonMap!);
          return result.isSuccess &&
              summary != null &&
              summary.files == _fileCount &&
              !summary.incomplete;
        },
        detail: (result) {
          final summary = RestoreSummary.fromJson(result.jsonMap ?? const {});
          return 'seq=${summary.seq} files=${summary.files} '
              'bytes=${summary.bytes}';
        },
      );
      if (restore == null) return _finish(false, steps, total, workDir, coreVersion, error, log);

      final same = await _directoriesMatch(sourceDir, restoreDir);
      steps.add(
        SliceStep(
          title: '逐文件比对恢复结果',
          ok: same,
          detail: same ? '$_fileCount 个文件 SHA-256 一致' : '恢复内容与源目录不一致',
          duration: Duration.zero,
        ),
      );
      log('${same ? '✓' : '✗'} 逐文件比对恢复结果 · ${same ? 'SHA-256 一致' : '内容不一致'}');
      if (!same) return _finish(false, steps, total, workDir, coreVersion, error, log);

      final verify = await step(
        title: '抽样校验',
        command: CoreCommand.verify,
        args: ['--sample', '1'],
        withPassword: true,
        passwordValue: password,
        accept: (result) {
          final summary = result.jsonMap == null
              ? null
              : VerifySummary.fromJson(result.jsonMap!);
          return result.isSuccess && summary != null && summary.isClean;
        },
        detail: (result) {
          final summary = VerifySummary.fromJson(result.jsonMap ?? const {});
          return 'local=${summary.localPacks} sampled=${summary.sampled} '
              'missing=${summary.missing?.length ?? 0}';
        },
      );
      if (verify == null) return _finish(false, steps, total, workDir, coreVersion, error, log);

      final doctor = await step(
        title: 'doctor --chain 一致性自检',
        command: CoreCommand.doctor,
        args: ['--chain'],
        withPassword: true,
        passwordValue: password,
        accept: (result) {
          final checks = result.jsonList
              ?.map((item) => DoctorCheck.fromJson(asJsonMap(item)))
              .toList();
          return result.isSuccess &&
              checks != null &&
              checks.isNotEmpty &&
              checks.every((check) => !check.status.isBlocking);
        },
        detail: (result) {
          final checks = result.jsonList
                  ?.map((item) => DoctorCheck.fromJson(asJsonMap(item)))
                  .toList() ??
              const <DoctorCheck>[];
          final warning = checks.where((check) => check.status == DoctorStatus.warn).length;
          return '${checks.length} 项检查，WARN=$warning，FAIL=0';
        },
      );
      if (doctor == null) return _finish(false, steps, total, workDir, coreVersion, error, log);

      return _finish(true, steps, total, workDir, coreVersion, error, log);
    } catch (caught) {
      error = '$caught';
      log('✗ 垂直切片异常终止：$caught');
      if (workDir != null) {
        log('! 保留现场：${workDir.path}');
      }
      return _finish(false, steps, total, workDir, coreVersion, error, log);
    }
  }

  VerticalSliceReport _finish(
    bool success,
    List<SliceStep> steps,
    Stopwatch total,
    Directory? workDir,
    String? coreVersion,
    String? error,
    void Function(String) log,
  ) {
    total.stop();
    final cancelled = _cancelRequested;
    String? keptWorkDir;
    if (workDir != null) {
      if (!success && !cancelled && keepWorkDirOnFailure) {
        keptWorkDir = workDir.path;
      } else {
        try {
          workDir.deleteSync(recursive: true);
        } catch (_) {
          keptWorkDir = workDir.path;
        }
      }
    }
    log(success
        ? '✓ M0 垂直切片通过（${total.elapsed.inMilliseconds} ms）'
        : cancelled
        ? '■ M0 垂直切片已取消'
        : '✗ M0 垂直切片失败${keptWorkDir == null ? '' : '，现场保留在 $keptWorkDir'}');
    return VerticalSliceReport(
      success: success,
      cancelled: cancelled,
      steps: List<SliceStep>.unmodifiable(steps),
      duration: total.elapsed,
      workDir: keptWorkDir,
      coreVersion: coreVersion,
      error: error,
    );
  }

  Future<void> _writeFixtureFiles(Directory sourceDir) async {
    await File(p.join(sourceDir.path, 'a.txt')).writeAsString('hello eimmortal\n');
    await File(p.join(sourceDir.path, 'sub', 'b.txt'))
        .writeAsString('desktop client vertical slice\n');
    final random = Random.secure();
    final bytes = List<int>.generate(
      _randomFileBytes,
      (_) => random.nextInt(256),
      growable: false,
    );
    await File(p.join(sourceDir.path, 'sub', 'rand.bin')).writeAsBytes(bytes);
  }

  Future<bool> _directoriesMatch(Directory source, Directory restored) async {
    final sourceFiles = await source
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    if (sourceFiles.length != _fileCount) return false;
    for (final file in sourceFiles) {
      final relative = p.relative(file.path, from: source.path);
      final restoredFile = File(p.join(restored.path, relative));
      if (!await restoredFile.exists()) return false;
      final left = await sha256.bind(file.openRead()).first;
      final right = await sha256.bind(restoredFile.openRead()).first;
      if (left != right) return false;
    }
    return true;
  }

  String _randomPassword() {
    const alphabet =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final random = Random.secure();
    return List<String>.generate(
      32,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }
}
