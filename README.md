# encry-immortals-ui

[`encry-immortals`](https://github.com/tangthinker/encry-immortals)（eimmortal）的桌面客户端，目标平台 **macOS 12+ / Windows 10+**。

> 状态：**M1 MVP 功能范围已完成**（2026-10-21）。已实现创建/加入库、解锁、仪表盘、备份、历史、恢复、校验、设置与 Key 导出；
> macOS release 已带签名 sidecar 并验证 bundle 内 SHA-256。Windows 构建脚本已提供，但尚未在 Windows 宿主实测；
> Developer ID 公证与 Authenticode 签名仍属于发布阶段工作。
>
> 技术结论见 [技术选型](docs/tech-selection.md)，进程与 JSON 契约见 [集成契约](docs/integration-contract.md)，
> 每轮开发记录见 [开发日志](docs/devlog.md)。

![创建/加入库](docs/assets/m1-onboarding.jpg)

![仪表盘](docs/assets/m1-dashboard.jpg)

更多界面：[解锁](docs/assets/m1-unlock.jpg) · [备份](docs/assets/m1-backup.jpg) · [历史](docs/assets/m1-history.jpg) ·
[恢复](docs/assets/m1-restore.jpg) · [校验](docs/assets/m1-verify.jpg) · [设置](docs/assets/m1-settings.jpg)。

## 已实现功能

| 流程 | 内容 |
|---|---|
| 创建新库 | 选择源目录与空 TargetDir → 设置主密码 → `init` → `export-key` → 强制保存 Armor Key |
| 加入已有库 | 选择 TargetDir 与本地源目录 → 粘贴 Armor Key → `init --join` → `import-key` → 主密码验证 → `doctor --chain` |
| 解锁 | 以 `log --json` 作为密码探针；密码只保存在内存，锁定/退出即清除 |
| 概览 | `status --chain` 的健康度、锚点、pack 统计、密文/逻辑体积、最近提交与警告 |
| 备份 | 源根目录固定；`--dry-run` 预演；实时进度/日志；截断提示与继续备份；`--break-lock` 重试 |
| 历史 | `log` 提交列表、`show` 变更明细、`ls --at` 文件树与按路径过滤 |
| 恢复 | 强制 `doctor --chain` 预检 → `restore --list-packs` 检查缺失 → 覆盖策略 → `--dry-run` 或正式恢复；支持跳过缺失 pack / 等待同步 |
| 校验 | `verify --sample N` / `--deep` 与 `doctor --chain`，展示 PASS/WARN/FAIL、缺失/损坏/抽样失败 |
| 设置 | 查看 profile/路径/核心完整性；修改 `session_max_mib`；重新验证密码后导出 Armor Key；写锁诊断；立即锁定；移除本地配置 |
| 应用保护 | 单实例文件锁；关闭窗口时若命令仍在运行会阻止退出并确认取消；全命令串行队列 |

界面为纯色深色主题，**不使用任何渐变**；不包含截图/自动自检等调试功能。

## 安全模型

- 主密码只经 **stdin** 传给 sidecar，不进入 argv/env/临时文件/日志；应用不提供“记住密码”。
- `init` / `import-key` / `export-key` 被标记为敏感命令；stdout 不进入运行日志。Armor Key 只在内存与剪贴板中出现。
- 所有 CLI 调用经过全局单飞队列；sidecar 崩溃/取消不会带走 UI。
- 释放版 sidecar 位于 `Encry Immortals.app/Contents/Resources/bin/eimmortal`，构建期签名并固定 SHA-256；
  release 忽略 `EIMMORTAL_CORE_PATH`，启动与每次解锁前都会重新校验。
- `doctor --chain` 是恢复的硬性前置；FAIL 时应用不会自动继续。
- 本地控制平面（`vault.meta`/`state.db`/journal）在应用数据目录，TargetDir 只存密文；移除配置**不会删除 TargetDir**。
- macOS 已关闭 App Sandbox（备份工具需要读取用户目录，且要执行 sidecar）；分发应使用 Developer ID + 公证。
- 首次读取“桌面/文稿”等受保护目录时，macOS 可能要求完全磁盘访问权限。

## 开发

### 前置

- Flutter 3.47.5 / Dart 3.13.4
- Xcode + CocoaPods（macOS）
- Go 1.27+（仅构建 sidecar 时需要）
- 上游核心仓库（当前基线 `v0.1.5-4-g340cade`，脚本会记录实际版本）

### 运行（开发模式）

```bash
flutter --no-version-check pub get

EIMMORTAL_CORE_PATH=/Users/tangthinker/code/go/encry-immortals/bin/eimmortal \
  flutter --no-version-check run -d macos
```

`EIMMORTAL_CORE_PATH` 只在 debug 构建生效；`flutter --version` 的 GitHub 版本检查在本机会卡住，统一使用 `--no-version-check`。

### 测试

```bash
flutter --no-version-check analyze
flutter --no-version-check test                         # 单元 + 组件测试，不需要 sidecar
flutter --no-version-check test test/core test/app      # 只跑非集成测试

# 真实链路：创建 → 备份 → 历史 → 恢复 → 校验 → 加入库
RUN_CORE_INTEGRATION=1 \
EIMMORTAL_CORE_PATH=/Users/tangthinker/code/go/encry-immortals/bin/eimmortal \
  flutter --no-version-check test test/integration
```

不启动 UI 的快速 core 冒烟：

```bash
dart run tool/vertical_slice.dart /path/to/eimmortal
```

### 构建 macOS release（带 sidecar）

```bash
EIMMORTAL_CORE_REPO=/Users/tangthinker/code/go/encry-immortals \
  ./tool/build_macos.sh
```

脚本会：

1. 从核心仓库构建 `CGO_ENABLED=0` sidecar，记录 `git describe` 版本；
2. **先 codesign sidecar，再计算 SHA-256**（签名会改写 Mach-O，顺序不能反）；
3. 用 `--dart-define=EIMMORTAL_CORE_SHA256=...` 构建 Flutter release；
4. 把已签名 sidecar 放入 `Contents/Resources/bin/eimmortal`，签名整个 app；
5. 校验 bundle 内 sidecar 哈希与构建期常量一致。

产物：

```text
build/macos/Build/Products/Release/Encry Immortals.app
```

验证 bundle：

```bash
dart run tool/verify_bundle.dart \
  "build/macos/Build/Products/Release/Encry Immortals.app" \
  "$(cat build/core/eimmortal.sha256)"
# integrity: verified
```

当前默认使用 **ad-hoc 签名**，仅用于本机验证；正式分发需要 Developer ID、hardened runtime 与 notarization。
可设置 `CODESIGN_IDENTITY="Developer ID Application: …"` 让脚本使用带 runtime/timestamp 的正式签名。

### 构建 Windows（未实测）

```powershell
.\tool\build_windows.ps1 -CoreRepo C:\path\to\encry-immortals
```

脚本构建 `eimmortal.exe` 与 GUI 子系统 `eimmortal-gui.exe`，复制到 Flutter release 的 `bin\` 并写入 `core-build.txt`。
发布前需 Authenticode 签名，并验证 Windows 上 GUI 子系统 sidecar 的 stdio 与锁行为。

## 目录结构

```text
lib/
  app/
    app_controller.dart     启动/单实例/核心校验/profile/解锁状态机
    screens/                onboarding、解锁、主壳层与六个功能页
    widgets/                卡片、状态、日志、文件树
  core/
    core_gateway.dart       sidecar 进程 IO、JSON、退出码、取消
    core_models.dart        CLI JSON 模型
    command_queue.dart      全局单飞队列
    app_paths.dart          macOS/Windows 应用数据目录
    profile*.dart           单 profile 持久化（0600）
    onboarding_service.dart 创建/加入库
    vault_session.dart      已解锁会话上的真实命令
    lock_inspector.dart     TargetDir/控制面写锁诊断
    progress.dart           stderr 进度解析（只用于显示）
    vertical_slice.dart     开发期真实链路冒烟
tool/
  build_core.sh             sidecar 构建 + 哈希
  build_macos.sh            release app + 签名 + 校验
  build_windows.ps1         Windows 构建（未实测）
  verify_bundle.dart        bundle 路径/哈希/版本验证
  vertical_slice.dart       终端版冒烟
```

## 已知限制

- 单 profile；不做定时/无人值守备份、自动更新、多 vault、文件预览、`compact`/`gc` 图形化。
- 应用使用自己的控制平面（`~/Library/Application Support/EncryImmortals/vault`），不是 CLI 的 `~/.eimmortal`。
  不要用 CLI/GUI 或其他客户端同时操作同一个 TargetDir；控制锁与锚点状态可能分叉。
- Windows 构建与 GUI 子系统 stdio 未实测；Windows 控制锁仍需上游 `LockFileEx` 改造（见技术选型 P0）。
- macOS release 仅 ad-hoc 签名；未公证，未做 Apple Silicon + Intel universal 单包。
- 空闲自动锁定未实现（仅手动锁定/退出清除密码）；大快照的 `ls` 仍一次加载完整文件树。
- 已做启动/备份后的 TargetDir 写锁检测与横幅提示，但尚未持久化“上次中断”的操作状态，也不会自动重试。

## 文档

- [技术选型](docs/tech-selection.md) — Flutter + sidecar 的取舍、架构、打包、风险与待确认项。
- [客户端 ↔ 核心 CLI 集成契约](docs/integration-contract.md) — 逐命令能力矩阵、密码/stdin、退出码、JSON、锁/取消、契约测试清单。
- [开发日志](docs/devlog.md) — 每个里程碑的目标、操作、结果、决策与风险。

## 核心仓库

- <https://github.com/tangthinker/encry-immortals>
- 当前核心最新 tag：`v0.1.5`；发布时应固定到 tag/commit，并重跑集成契约测试。
