import 'core_exit_code.dart';

/// 子进程 stdin 的用途。stdin 是单一通道：密码、Armor Key 不会同时出现。
enum CoreStdin {
  none,
  password,
  armorKey,
}

/// MVP 阶段允许 GUI 调用的命令集合。
///
/// 不在这个枚举里的命令（cat / manifest / gc / compact / rebuild-state / note）
/// 属于“高级或破坏性操作”，v1 不暴露。
enum CoreCommand {
  version(
    name: 'version',
    supportsJson: false,
    stdin: CoreStdin.none,
    sensitive: false,
  ),
  status(
    name: 'status',
    supportsJson: true,
    stdin: CoreStdin.none,
    sensitive: false,
    acceptsPassword: true,
  ),
  log(
    name: 'log',
    supportsJson: true,
    stdin: CoreStdin.password,
    sensitive: false,
  ),
  show(
    name: 'show',
    supportsJson: true,
    stdin: CoreStdin.password,
    sensitive: false,
  ),
  ls(
    name: 'ls',
    supportsJson: true,
    stdin: CoreStdin.password,
    sensitive: false,
  ),
  backup(
    name: 'backup',
    supportsJson: true,
    stdin: CoreStdin.password,
    sensitive: false,
    writesTarget: true,
  ),
  restore(
    name: 'restore',
    supportsJson: true,
    stdin: CoreStdin.password,
    sensitive: false,
    writesDest: true,
  ),
  verify(
    name: 'verify',
    supportsJson: true,
    stdin: CoreStdin.password,
    sensitive: false,
  ),
  doctor(
    name: 'doctor',
    supportsJson: true,
    stdin: CoreStdin.none,
    sensitive: false,
    acceptsPassword: true,
    jsonOnFailure: true,
  ),
  init(
    name: 'init',
    supportsJson: false,
    stdin: CoreStdin.password,
    sensitive: true,
    writesTarget: true,
  ),
  initJoin(
    name: 'init',
    supportsJson: false,
    stdin: CoreStdin.none,
    sensitive: false,
    writesTarget: true,
  ),
  importKey(
    name: 'import-key',
    supportsJson: false,
    stdin: CoreStdin.armorKey,
    sensitive: true,
  ),
  exportKey(
    name: 'export-key',
    supportsJson: true,
    stdin: CoreStdin.none,
    sensitive: true,
  );

  const CoreCommand({
    required this.name,
    required this.supportsJson,
    required this.stdin,
    required this.sensitive,
    this.acceptsPassword = false,
    this.writesTarget = false,
    this.writesDest = false,
    this.jsonOnFailure = false,
  });

  /// 传给 CLI 的命令名（`initJoin` 与 `init` 共用）。
  final String name;

  /// 该命令是否支持 `--json`。
  final bool supportsJson;

  /// 默认情况下该命令从 stdin 读取什么。
  final CoreStdin stdin;

  /// 输出或输入是否含 Armor Key 等敏感材料，日志器必须避让。
  final bool sensitive;

  /// 是否允许在带 `--chain` 等参数时使用 `--password-fd`。
  final bool acceptsPassword;

  /// 是否写 TargetDir（运行期间必须单飞）。
  final bool writesTarget;

  /// 是否写用户选择的目标目录。
  final bool writesDest;

  /// 是否可能在非零退出时仍输出 JSON（doctor / restore / verify）。
  final bool jsonOnFailure;

  /// 给定参数时，本命令实际是否应通过 stdin 传密码。
  ///
  /// `status` / `doctor` 只有带 `--chain` 才解锁；其余命令由 [stdin] 决定。
  bool needsPasswordFor(List<String> args) {
    if (stdin == CoreStdin.password) return true;
    if (!acceptsPassword) return false;
    return args.contains('--chain');
  }

  /// 给用户看的动作名。
  String get label => switch (this) {
    version => '检查核心版本',
    status => '读取库状态',
    log => '读取提交历史',
    show => '查看提交详情',
    ls => '浏览快照文件树',
    backup => '执行备份',
    restore => '恢复快照',
    verify => '校验数据完整性',
    doctor => '运行一致性自检',
    init => '创建新库',
    initJoin => '加入已有库',
    importKey => '导入 Armor Key',
    exportKey => '导出 Armor Key',
  };

  /// 成功/失败映射的统一说明入口。
  CoreExitCode mapExitCode(int code) => CoreExitCode.fromCode(code);
}
