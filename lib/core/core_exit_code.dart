/// 与 encry-immortals 核心 CLI 约定的稳定退出码。
///
/// 见 `docs/integration-contract.md` 第 4.2 节。GUI 必须按退出码做用户可执行的
/// 引导，而不是把 stderr 原样当成“密码错误”。
enum CoreExitCode {
  success(0, '成功'),
  unknown(1, '未分类错误'),
  usage(2, '用法 / 参数 / 配置错误'),
  password(10, '密码错误或 vault.meta 损坏'),
  chain(11, '链断裂 / 回滚 / 截断'),
  corrupt(12, '数据损坏'),
  incomplete(13, '数据不完整（pack 缺失）'),
  noSpace(14, '磁盘空间不足'),
  locked(20, '锁被占用'),
  unsupported(21, '不支持的内容'),
  interrupted(130, '被中断'),
  terminated(-1, '进程被终止');

  const CoreExitCode(this.code, this.label);

  final int code;
  final String label;

  bool get isSuccess => this == success;

  /// 是否是“不能继续写，但可以只读诊断”的错误。
  bool get isSafetyStop => this == chain || this == corrupt || this == incomplete;

  /// 是否是用户可以直接重试的错误。
  bool get isRetryable => this == locked || this == noSpace;

  String get guidance => switch (this) {
    success => '操作成功。',
    unknown => '查看运行日志；不要自动重试写操作，必要时导出诊断信息。',
    usage => '检查配置与参数，必要时回到设置页修正后重试。',
    password => '确认主密码后重试；若换过机器，尝试重新导入 Armor Key。',
    chain => '停止写入。先运行 doctor --chain 查看链状态，不要自动修复。',
    corrupt => '停止写入。运行 verify --deep 保留证据，并考虑从其他副本恢复。',
    incomplete => '等待网盘同步完成后重试；渐进恢复需要明确选择缺失的 pack。',
    noSpace => '清理磁盘或更换 TargetDir 后重试。',
    locked => '确认没有其他 eimmortal 进程；不要静默删除锁文件。',
    unsupported => '检查排除规则与不支持的路径/文件类型后重试。',
    interrupted => '上次操作被中断；检查写锁状态，确认后再重试。',
    terminated => '子进程被系统终止；检查锁状态后重试。',
  };

  static CoreExitCode fromCode(int code) {
    if (code < 0) return terminated;
    for (final value in values) {
      if (value.code == code) return value;
    }
    return unknown;
  }
}
