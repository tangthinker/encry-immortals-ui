# 开发日志

> 项目：encry-immortals-ui（eimmortal 桌面客户端）
> 约定：每个里程碑按时间倒序记录「目标 / 操作 / 结果 / 决策 / 风险 / 下一步」。命令与输出只保留可复现的关键部分，不记录密码、Armor Key、明文文件列表。

---

## 2026-10-21 19:07 · M0 垂直切片完成（脚手架 + 网关 + UI 壳层）

### 目标

把选型结论落成可运行的工程：Flutter 桌面壳 + `CoreGateway` + 串行队列，用真实 sidecar 跑通
`init → backup → log → restore → verify`，并把过程写进仓库。

### 交付物

| 路径 | 内容 |
|---|---|
| `lib/core/core_gateway.dart` | sidecar 定位后的进程网关：argv 构造、stdin 密码、并发读 stdout/stderr、JSON 解析、退出码映射、取消/超时 |
| `lib/core/core_process.dart` | `CoreProcess` / `CoreProcessLauncher` 抽象 + `Process.start` 实现；环境变量白名单 |
| `lib/core/core_locator.dart` | macOS bundle / Windows 安装目录路径解析、debug 环境覆盖、SHA-256 校验 |
| `lib/core/command_queue.dart` | 全局单飞队列，失败不阻塞后续任务，支持取消当前任务 |
| `lib/core/core_models.dart` | `VaultStatus` / `CommitEntry` / `BackupSummary` / `RestoreSummary` / `VerifySummary` / `DoctorCheck` 等手写 `fromJson` |
| `lib/core/vertical_slice.dart` | 13 步真实链路自检，逐文件 SHA-256 比对，支持取消 |
| `lib/core/vault_config.dart` | 最小 `config.toml` 生成 + POSIX 0600 |
| `lib/app/**` | 概览 / 自检 / 关于三页壳层，Riverpod 3 状态，日志面板 |
| `test/core/**` | 网关、队列、模型、配置单测（30 个用例） |
| `test/integration/vertical_slice_test.dart` | 真实 sidecar 集成测试（默认 skip，需显式开启） |
| `tool/vertical_slice.dart` | 终端版垂直切片，不依赖 Flutter UI |
| `docs/assets/m0-*.jpg` | M0 概览与自检结果截图 |

### 脚手架

- 为不覆盖已有 `README.md` / `docs/`，先在 `/tmp/eimui.*` 生成，再只复制 `lib/`、`test/`、`macos/`、`windows/`、`pubspec.*`、`analysis_options.yaml`、`.metadata`、`.gitignore`。
- 依赖保持最小：`flutter_riverpod 3.4.3`、`crypto 3.0.7`、`path 1.9.1`；不引入 freezed/json_serializable，避免 CLI 字段演进时的生成器负担。
- `flutter create` 生成 54 个文件；`flutter pub get` 成功。

### 网关实现要点

- 参数固定为 `--config <cfg> [--json] [--password-fd 0] <command> [args...]`；密码永远不进 argv，`import-key` 的 Armor Key 只走 stdin。
- stdout/stderr 并发读取；stdout 上限 16 MiB，stderr 环形上限 256 KiB，避免大 `log/show` 阻塞 UI。
- 先等退出码再解析 JSON；非零退出仍尝试解析（doctor/restore/verify 会先输出 JSON）。
- 成功但 JSON 解析失败 → `protocolError`，不静默当成功。
- 敏感命令（`init` / `export-key` / `import-key`）的 `CoreResult.redacted()` 清空输出；日志只记录 `exit/duration/errorSummary`。
- 取消：先 SIGTERM，5 秒后 SIGKILL；Windows 退化为 `TerminateProcess`。结果标记 `cancelled`，不依赖 130。
- 环境只透传 `PATH/HOME/TMPDIR/LANG/APPDATA/...` 白名单，避免用户环境改变 CLI 行为。

### 垂直切片（真实 sidecar）

终端运行：

```bash
dart run tool/vertical_slice.dart /Users/tangthinker/code/go/encry-immortals/bin/eimmortal
```

结果：**13/13 通过，5.315 s**。关键断言：

| 步骤 | 实测 |
|---|---|
| `init`（stdin 密码） | exit 0，~1.3 s，vault.meta 生成；Armor Key 只留内存 |
| `export-key --json` | armor 可解析，不写日志 |
| 空 `log --json` | `[]` |
| `backup --json` | seq=1，added=3，pack≈1.05 MB |
| `status` / `status --chain` | schema=1；`referenced=1`、`missing=0`、`verified=true` |
| 错误密码 `log` | exit 10，stdout 0 字节（符合契约） |
| `restore` | 3 个文件，逐文件 SHA-256 与源目录一致 |
| `verify --sample 1` | missing=0、sample 失败=0 |
| `doctor --chain` | 10 项检查，FAIL=0 |

UI 内置同样的切片：`docs/assets/m0-selfcheck.jpg`，应用内 **13/13 · 5.28 s**。

### UI 与构建

- 三页壳层：概览（运行环境 / M0 进度 / 边界）、自检（实时步骤 + 日志 + 取消）、关于（版本与文档）。
- 首次 `flutter build macos --debug` 成功；Xcode 只有 CoreSimulator 版本过旧与 Run Script 的无害警告。
- 关键问题：Flutter 模板默认开启 **macOS App Sandbox**，沙盒内无法执行 `EIMMORTAL_CORE_PATH` 指向的外部 sidecar，概览会显示“核心不可用”。这与选型文档“备份工具不走 App Sandbox”的结论一致，已从 `DebugProfile.entitlements` / `Release.entitlements` 移除 `com.apple.security.app-sandbox`。重新构建后核心就绪。
- 应用名与窗口：`PRODUCT_NAME = Encry Immortals`，初始 1220×820、最小 960×640；Windows 标题同步。
- 截图受限：`screencapture` 在当前会话没有屏幕录制权限，改用 **debug-only 应用内截图钩子**：
  - `EIMMORTAL_SCREENSHOT=/tmp/x.png`：启动 3 秒后把根 `RepaintBoundary` 保存为 PNG；
  - `EIMMORTAL_SCREENSHOT_DELAY=12`：等待自检完成；
  - `EIMMORTAL_AUTORUN_SELFTEST=1`：debug 构建自动切到自检页并运行。
  - release 构建 `kDebugMode=false`，这些钩子不会执行。

### 遇到的问题与处理

1. `flutter --version` 卡在 `git remote-https origin https://github.com/flutter/flutter.git`：本机 github 不可达而 pub.dev 正常。所有 Flutter 命令加 `--no-version-check`。
2. Riverpod 3 的 `AsyncValue` 没有 `valueOrNull`（3.4.3 源码只有 `value`），改用 `value`。
3. `flutter test` 首次并行编译时一个用例缺 `core_exit_code.dart` 导入导致 “Dart compiler exited unexpectedly”；补齐导入后正常。
4. 自检中“错误密码探针”是预期 exit 10，最初 UI 用红色显示 `exit 10`，易误读为失败；改为灰色 `exit 10 · 预期`。
5. 截图中的 `CoreSimulator is out of date` 只影响 iOS 模拟器，不影响 macOS 产物。

### 验证

```bash
flutter --no-version-check analyze                 # No issues found
flutter --no-version-check test                    # 30 passed, 1 skipped（集成测试默认 skip）
RUN_CORE_INTEGRATION=1 \
  EIMMORTAL_CORE_PATH=.../bin/eimmortal \
  flutter test test/integration                    # 13/13 passed
flutter --no-version-check build macos --debug     # ✓ Built Encry Immortals.app
flutter --no-version-check build macos --release   # ✓ 42.1 MB
```

`codesign -d --entitlements` 确认 release 产物已无 `com.apple.security.app-sandbox`；release 尚未把 sidecar 放进
`Contents/Resources/bin/`，因此当前 release 会显示“核心不可用”，这是打包阶段待补的项，不是网关回归。

### 风险 / 未完成

- [ ] `CoreGateway` 尚未接入真实 profile / onboarding；目前只有临时库自检。
- [ ] 未做单实例锁、退出保护、锁残留修复 UI。
- [ ] sidecar 尚未随 app bundle 打包，release 构建没有固定 SHA-256；`EIMMORTAL_CORE_PATH` 只在 debug 生效。
- [ ] 未做 macOS 签名/公证、Windows 构建与 GUI 子系统 sidecar 验证。
- [ ] 自检运行期间 UI 仍可点“概览”等页；命令队列已具备，但真实写操作入口尚未统一接入队列。

### 下一步（M1）

1. Profile 存储（source root 固定、config 0600、应用数据目录）与 onboarding 创建/加入库。
2. 解锁会话：`log` 探针 + 内存密码 + 锁屏/超时清理。
3. 仪表盘接 `status --chain`；备份 dry-run/正式/进度/截断；历史与恢复前 `doctor --chain`。
4. 把真实操作入口全部改成经 `CommandQueue`，并补单实例与退出保护。

---

## 2026-10-21 · M0 开始：环境勘察与脚手架

### 环境

| 项 | 值 |
|---|---|
| 主机 | macOS 27.0.1 (26A434)，Apple Silicon |
| Flutter | 3.47.5 (stable, 6a19cca5) |
| Dart | 3.13.4 |
| Xcode | /Applications/Xcode.app/Contents/Developer |
| CocoaPods | 1.17.0 |
| Go | 1.27.1 darwin/arm64 |
| 核心仓库 | `/Users/tangthinker/code/go/encry-immortals`，`v0.1.5-4-g340cade` |
| 核心二进制 | `bin/eimmortal`，报 `eimmortal 0.1.0-dev` |

### 操作与结果

1. 通读 `docs/tech-selection.md`、`docs/integration-contract.md`，确认本轮范围是 M0 垂直切片。
2. `flutter --version` 卡在 `git remote-https origin https://github.com/flutter/flutter.git`：本机访问 github 超时（`curl https://github.com` 返回 000），而 pub.dev 正常。后续 Flutter 命令需加 `--no-version-check` 或接受版本检查超时；不影响本地构建。
3. 上游核心仓库与已构建的 `bin/eimmortal` 均存在，可直接用于契约测试；当前 HEAD 比 `v0.1.5` 多 4 个文档提交，代码基线仍为 `340cade`。
4. 已确认 pub 缓存包含 Riverpod 3.4.3、go_router 17.5.0、file_selector 1.1.0、path_provider 2.1.6、window_manager 0.5.2 等候选依赖。

### 决策

- 本轮先做 **sidecar 网关 + 垂直切片**，UI 保持在最小可用壳层；理由：文档把进程/JSON/锁/取消列为最大风险，先验证底座再铺页面。
- 架构落点：
  - `lib/core/`：纯 Dart 的 sidecar 适配层（不依赖 Flutter），便于单测与后续复用。
  - `lib/app/`：Flutter 应用层（队列、状态、页面）。
- sidecar 开发期通过 `EIMMORTAL_CORE_PATH` 指向上游 `bin/eimmortal`；release 只允许 bundle 内路径（后续在打包阶段实现 SHA-256 校验）。
- 暂不引入代码生成（freezed/json_serializable），手写 `fromJson`，避免 CLI 字段演进时的生成器负担。

### 风险 / 待验证

- [ ] `flutter create` / 首次 `pub get` 是否受 github 不可达影响。
- [ ] macOS 上 Flutter 桌面构建（CocoaPods）是否可用。
- [ ] 真实 sidecar 垂直切片的耗时与内存（预期 init ~2s / 峰值 ~1.1GB）。
- [ ] 取消后 TargetDir 锁残留的处理（本切片先只检测，不自动修复）。

### 下一步

- [ ] 生成 macOS/Windows 桌面脚手架，合并 `.gitignore` / `README`。
- [ ] 实现 `CoreGateway` 与 `CommandQueue`。
- [ ] 用真实 sidecar 跑通 init → backup → log → restore → verify。
