import 'dart:io';

/// 对 `dart:io` Process 的最小抽象，便于用假的 sidecar 做单元测试。
abstract interface class CoreProcess {
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;

  void write(List<int> bytes);

  Future<void> closeStdin();

  /// 发送终止信号；返回是否成功发出。Windows 上会退化为 TerminateProcess。
  bool kill([ProcessSignal signal]);
}

abstract interface class CoreProcessLauncher {
  Future<CoreProcess> launch(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}

class SystemCoreProcessLauncher implements CoreProcessLauncher {
  const SystemCoreProcessLauncher();

  @override
  Future<CoreProcess> launch(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: false,
    );
    return SystemCoreProcess(process);
  }
}

class SystemCoreProcess implements CoreProcess {
  SystemCoreProcess(this._process);

  final Process _process;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void write(List<int> bytes) => _process.stdin.add(bytes);

  @override
  Future<void> closeStdin() => _process.stdin.close();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    // Windows 不支持 POSIX 信号，Dart 会直接 TerminateProcess。
    if (Platform.isWindows) return _process.kill();
    return _process.kill(signal);
  }
}

/// 只向核心传递最小环境变量集合。
///
/// 不传任何密码相关变量；不传 `EIMMORTAL_*`，避免用户环境意外改变 CLI 行为。
Map<String, String> buildCoreEnvironment([Map<String, String>? source]) {
  final env = source ?? Platform.environment;
  const keys = <String>[
    'PATH',
    'HOME',
    'USERPROFILE',
    'TMPDIR',
    'TEMP',
    'TMP',
    'LANG',
    'LC_ALL',
    'LC_CTYPE',
    'SystemRoot',
    'SYSTEMROOT',
    'SystemDrive',
    'SYSTEMDRIVE',
    'APPDATA',
    'LOCALAPPDATA',
    'USERNAME',
    'USER',
    'LOGNAME',
  ];
  final result = <String, String>{};
  for (final key in keys) {
    final value = env[key];
    if (value != null && value.isNotEmpty) result[key] = value;
  }
  return result;
}

/// 给 sidecar 一个稳定的工作目录，避免继承 GUI 的 `/` 或安装目录。
String? defaultCoreWorkingDirectory([Map<String, String>? source]) {
  final env = source ?? Platform.environment;
  final home = env['HOME'] ?? env['USERPROFILE'];
  if (home == null || home.isEmpty) return null;
  return Directory(home).existsSync() ? home : null;
}
