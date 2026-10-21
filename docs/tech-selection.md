# encry-immortals 桌面客户端技术选型

> 状态：Proposed（待确认） · 日期：2026-10-21 · 目标平台：macOS 12+（Apple Silicon 优先）、Windows 10/11 x64
>
> 结论先行：**Flutter 3.47 桌面端 + Go CLI sidecar（子进程）**。不把 Go 核心编成 c-shared / FFI 嵌进 UI 进程，也不在 Dart/TS 里重写核心。v1 不上常驻 daemon，不做自动更新和无人值守定时备份。
>
> 本文只做选型和架构决策，不包含实现代码。建议先用 2–3 天做 spike，验证第 8 节的三个未知项，再进入 UI 开发。
>
> 配套的逐命令协议与测试清单见 [integration-contract.md](integration-contract.md)。

---

## 1. 一页结论

| 决策项 | 选择 | 一句话理由 |
|---|---|---|
| UI 框架 | **Flutter 3.47.5 / Dart 3.13.4** | 安全攻击面小、无 Chromium/Node 运行时、体积和常驻内存低；桌面端已是一等公民；本机工具链已就绪 |
| 核心集成 | **每命令一个 Go 子进程（sidecar）** | 核心是完整 CLI，已有 `--json` / 稳定退出码 / `--password-fd`；零改核心即可集成，且 1 GiB Argon2 的内存峰值被隔离在子进程 |
| 核心代码引用 | **git submodule 固定 tag/commit，CI 构建 sidecar** | 可复现、不复制源码；纯 Go `CGO_ENABLED=0`，macOS 上 5 秒内可交叉出 Windows/macOS 两种架构 |
| 密码传递 | **stdin（`--password-fd 0`）** | 不进程参数、不环境变量、不落盘；已实测可用，`init` 会跳过二次确认 |
| 进程模型 | **全局单飞队列，所有命令串行** | 控制平面是单写者锁；并发命令会以 E20 失败。`status` 也会拿锁 |
| 打包 | macOS Developer ID + notarization；Windows Authenticode + Inno Setup/MSIX | 备份工具需要读取用户目录，不建议走商店分发的沙箱/虚拟化路径（macOS App Sandbox / Windows MSIX 限制） |
| 上游必做 | Windows 控制锁（发布阻塞项）、取消/锁清理、结构化进度、JSON 补齐 | 这四项直接决定 Windows 可用性和 GUI 体验；不解决也能做，但会变成大量补丁式 workaround |
| v1 不做 | 自动更新、无人值守定时、多 vault、文件预览、`compact`/`gc` 的图形化 | 先把「创建/加入 → 解锁 → 备份 → 历史 → 恢复 → 校验」闭环做扎实 |
| 备选方案 | **Electron + 同一个 sidecar** | 如果“macOS 单包 universal + 开箱即用的自动更新 + Web 团队”是硬约束，改选 Electron；详见第 5 节 |

**一句话决策**：这个产品的核心价值在 Go 的加密与存储管线，客户端只是安全的操作台。用 sidecar 把核心完整保留，用 Flutter 做一层薄而稳的桌面 UI，是改动最小、风险最低的组合。

---

## 2. 先看代码：这个核心适合怎么接

### 2.1 它是 CLI，不是可链接的库

- 所有实现都在 [`internal/`](https://github.com/tangthinker/encry-immortals/tree/main/internal) 下，没有 `pkg/` 公共 API。外部 Go module **不能** import `internal/...`；要让 UI 直接链接核心，必须先在核心仓库里新增一个导出的 `pkg/client` 或 `cmd/eimmortal serve` 层。
- 纯 Go，`CGO_ENABLED=0`，[`scripts/release-build.sh`](https://github.com/tangthinker/encry-immortals/blob/main/scripts/release-build.sh) 一次产出 linux/darwin/windows 五个目标。本地实测交叉编译 `windows/amd64`、`darwin/amd64`、`darwin/arm64` 各 4–5 秒，strip 后约 8.9 MB；两个 macOS 架构 `lipo` 成 universal 后 17 MB。
- 这意味着：**sidecar 的构建成本几乎为零**，而 FFI 需要引入 cgo、每个目标一套 C 工具链、新增公共 API，并把 Go runtime 装进 GUI 进程。

### 2.2 CLI 已经为“非交互客户端”设计过

[`internal/cli/cli.go`](https://github.com/tangthinker/encry-immortals/blob/main/internal/cli/cli.go) 和 [`docs/spec/10-cli-and-config.md`](https://github.com/tangthinker/encry-immortals/blob/main/docs/spec/10-cli-and-config.md) 已经定义了稳定契约：

- `--json`：结果 JSON 走 stdout，人类进度走 stderr；`--json` 不污染管道。
- 退出码是稳定契约：`0` 成功、`1` 未分类、`2` 用法/配置、`10` 密码或 vault.meta 问题、`11` 链/回滚、`12` 损坏、`13` 不完整、`14` 空间不足、`20` 锁、`21` 不支持的内容、`130` 中断。
- `--password-fd <n>` 从文件描述符读一行；`--password-file` 从 0600 文件读；**没有** `--password` 明文参数。`--password-fd 0` 可以直接接 GUI 的 stdin 管道。
- `status --json` 有显式的 `schema: 1`，适合做仪表盘；`log`/`show`/`ls` 也都有 JSON 结构。
- 所有可能进脚本的命令都支持完全非交互；危险操作在非 TTY 下要求显式 `--yes`。

这不是“勉强可以包一层”，而是核心作者已经把 GUI/脚本集成当成一等情况考虑过。

### 2.3 实测：解锁成本与内存峰值

在本机（Apple Silicon macOS，样本数据）用本地 `main` `32889e1` 构建的 `0.1.0-dev` 二进制跑通（写作时 main 已到 `340cade`，`32889e1..340cade` 仅 README 变更，代码未变）：

| 操作 | 耗时 | 峰值 RSS | 说明 |
|---|---:|---:|---|
| `init`（密码走 stdin） | ~2 s | ≈1.1 GB（KDF 参数） | Argon2id 校准，一次性；峰值按 m=1 GiB 推算 |
| `backup`（3 文件 / 1 MiB） | ~0.51 s | 1,096,105,984 B | 含解锁、扫描、写入、提交 |
| `log` | ~0.46 s | 1,090,912,256 B | 纯读取也要解锁 |
| `status --chain` | ~0.46 s | 1,090,764,800 B | 链统计 + 锚点检查 |
| `restore`（1 MiB） | ~0.46 s | 1,093,222,400 B | 恢复结果与源目录 `diff -r` 一致 |
| `status`（不带 `--chain`） | ~0.014 s | 很小 | 不需要密码，不解锁 |
| 密码错误 | — | — | 退出码 10，stdout 为空 |
| 无 TTY、无密码源 | — | — | 退出码 2，提示用 `--password-fd` |
| 并发第二个命令 | — | — | 退出码 20（控制锁被占用） |

Argon2id 的 1 GiB 是**安全参数，不应为了 GUI 调低**。这带来两个直接结论：

1. **不要把核心链进 UI 进程**：每次解锁会给 GUI 增加 1.1 GB 峰值，OOM 或崩溃会直接带走界面；sidecar 则把峰值关在子进程里，退出即释放。
2. **不要并发跑命令**：两个解锁就是 2.2 GB，而且控制锁本来就禁止并发。GUI 必须有一个全局命令队列。

### 2.4 单写者与锁：GUI 必须尊重的硬约束

- 每个命令进入 `openSession` 时都会拿控制平面的排他锁。Unix 上是 `flock`，进程退出自动释放；Windows 上是 [`control_other.go`](https://github.com/tangthinker/encry-immortals/blob/main/internal/lock/control_other.go) 的 `O_EXCL` 标记文件，**进程崩溃/被强杀后文件会留下**，后续所有命令都会 E20，错误信息让用户手工删除。注意 `backup --break-lock` 也救不了：控制锁在 `openSession` 里就先于命令处理被获取了。
- 写入 TargetDir 时还有跨主机 `.eimmortal.lock`。实测在备份中途 `SIGTERM`：退出码 130，`.eimmortal.lock` 留下；下一次 backup 退出 20；`backup --break-lock` 可以恢复。
- 所以 GUI 不能“随时刷新状态”：备份运行时点状态页，状态命令也会因为控制锁而失败。正确做法是**所有 CLI 调用经过同一个队列**，运行中禁用会拿锁的操作，结束后统一刷新。
- 取消按钮不能简单地 `kill`：在 Windows 上强杀会留下控制锁 + 目标锁。GUI 必须有“上次被中断，修复写锁后重试”的状态和明确的用户确认；上游最好提供优雅取消或 `lock repair` 命令。

### 2.5 一个 TargetDir 只能对应一个源根

README 和 `docs/usage.md` 都写了这一点，但 GUI 很容易忽略。实测把同一个 TargetDir 的 `--source` 从 A 目录换成 B 目录，backup 仍然“成功”提交了 seq=2，但下一次链加载直接 E12（对非空目录发 RMDIR）。这不是核心 bug，是使用约束；但 GUI 如果让用户在设置里随手改源目录，就会制造这种不可逆的语义破坏。

**GUI 必须把 source root 作为 profile 的一部分固定下来**：创建 vault 时记录，之后只允许“新建另一个 vault/profile”，不允许在同一个 TargetDir 上换源根。上游若能在 `vault.meta` 里记录 source root 更好，但那是格式变更，v1 不应为它冒险。

### 2.6 JSON 覆盖并不完整

已确认的缺口（直接影响 UI，不影响 sidecar 选型）：

- `init` / `init --join` / `import-key` **没有 `--json`**；`init` 还把 Armor Key 打印在人类可读 stdout 里。GUI 必须捕获到内存、绝不落日志，并在 init 后调用 `export-key --json` 拿结构化结果。
- `backup --dry-run --json` 缺少 `estimated_packs` / `estimated_bytes`（人类输出里有，JSON 结构里没有）。
- 进度是中文人类文本（每秒一行），不是结构化事件；GUI 可以展示为日志，但做精确进度条需要解析或补协议。
- `cat` 输出原始文件字节，不是 JSON；v1 不建议做文件预览。
- `doctor` / `restore` / `verify` 可能**先输出 JSON，再以非零退出码结束**（例如 doctor 有 FAIL → E12，restore 缺 pack → E13）。网关不能“非零就丢弃 stdout”，要按命令解析。
- `restore` 当前**没有** `--anchor` / `--i-accept-unverified`；它自己也不校验本地锚点。要防云端回滚，GUI 必须在 restore 前跑 `doctor --chain` 并把 FAIL 当作硬停止。
- `status --chain` 在密码错误时可能只加 warning 并返回 0，而且 `verified` 仍可能保持 `true`（它是解锁前按锚点算的）。不能把它当作“解锁成功/已验证”的判据；用 `log` 做解锁探针，并检查 `warnings` 是否含“未能取得主密码/无法解锁/链校验失败”。

这些都应该在 `docs/integration-contract.md` 里冻结成客户端协议，并由集成测试覆盖。

---

## 3. 集成方式选型：为什么是子进程

| 方案 | 需要改核心？ | 构建复杂度 | 内存/崩溃隔离 | 密码暴露面 | 结论 |
|---|---|---|---|---|---|
| **A. 子进程 sidecar（推荐）** | 不需要（最多补 JSON/进度） | 低：`go build` 即可，纯 Go 交叉编译 | 好：1.1 GB 峰值在子进程，崩溃不带走 UI | 密码经 stdin 管道；需校验 sidecar 完整性 | **采用** |
| B. c-shared / FFI（Dart FFI、Node koffi） | 要新增公共 API；`internal/` 不能直接 import | 高：cgo + 每个目标 C 工具链；Windows 交叉需 mingw；macOS universal 要 lipo c-archive | 差：1.1 GB 在 UI 进程；crypto/panic 直接杀 UI | 密钥在 UI 进程内 | 否 |
| C. 常驻 Go daemon / 本地 HTTP | 要新增 serve 层 | 中 | 中 | 密钥常驻，违反“无常驻进程/不长持密钥”的既有安全取舍 | 否（v1） |
| D. 在 Dart/TS 重写核心 | 重写 | 极高 | 取决于实现 | 重新实现加密/格式，兼容性与审计风险不可接受 | 否 |

补充说明：

- 公平地说，FFI 有一个真实优势：核心与 UI 在同一个签名产物内，少一个可被替换的 sidecar。但代价是 1.1 GB Argon2 进入 UI 进程、cgo/多工具链构建、以及 `internal/` 到公共 API 的重构；对本项目不划算。
- **gomobile 不覆盖桌面端**；`-buildmode=c-shared` 在 macOS 可行，但 Windows 需要 cgo + gcc/mingw，macOS universal 还要把两个 c-archive 合起来。当前核心发布是 `CGO_ENABLED=0` 的五个目标，改成 c-shared 是明显的构建退化。
- **常驻 daemon / 本地 HTTP** 看起来能省掉每次 0.46 s 的解锁，但会把主密码/派生密钥长期留在内存，违反 [`docs/security.md`](https://github.com/tangthinker/encry-immortals/blob/main/docs/security.md) 和 spec 10.9 的“无常驻进程”取舍；还要引入 socket/端口鉴权、生命周期、孤儿清理。0.46 s 的解锁成本不值得换这些。
- **常驻 sidecar over stdin/stdout（JSON-RPC）** 是比 HTTP daemon 更干净的 v2 方向：一次解锁、串行、结构化进度，不开放端口；代价是密钥驻留更久、生命周期/崩溃恢复更复杂。v1 不做，但如果后续解锁成本变得不可接受，它比 FFI 更值得评估。
- **子进程的唯一新增攻击面**是“sidecar 二进制被替换后偷密码”。这可以用签名 + 构建期固定 SHA-256 + 不允许用户自定义核心路径来缓解；详见 6.5。

---

## 4. sidecar 进程协议（客户端必须按这个实现）

### 4.1 调用形状

```text
eimmortal --config <config> --json --password-fd 0 <command> [args...]
```

- `stdin`：需要密码的命令写入 `password + "\n"`，然后立即关闭；`import-key` 写 Armor Key；其余命令不写。
- `stdout`：只读 JSON（或 `version` 的文本）；`cat` 例外，是原始字节。
- `stderr`：进度、日志、错误；按行流式读取，展示在“运行日志”面板。
- 不经过 shell；参数用数组传递，避免空格/中文/引号问题。
- 不把密码放进 argv/env/临时文件；不要用 `--password-file` 做交互式操作。
- `stdin` 是单一通道：需要密码的命令只收密码，`import-key` 只收 Armor Key；没有命令同时需要两者。
- 每个命令单独起进程；进程退出后释放 1.1 GB 峰值。不要为了“省解锁”而并发或常驻。

### 4.2 全局单飞队列

- 除 `version`/`help` 外，几乎所有命令都会拿控制锁（`status`、`export-key`、`doctor` 也不例外）。
- GUI 维护一个串行队列：同一时刻最多一个 CLI 子进程；运行中禁用“刷新/备份/恢复/校验”等入口，只允许取消。
- 不要在备份过程中轮询 `status`；备份结束后再刷新。
- 应用做单实例锁，避免两个 GUI 同时操作同一个 vault。

### 4.3 退出码与结果的处理

- 先看退出码，再看 stdout 是否可解析；**非零退出不一定没有 JSON**（doctor/restore/verify）。
- 映射建议：
  - `0`：成功；若有 JSON 就渲染结果。
  - `2`：配置/参数错误 → 引导到设置页，展示 stderr。
  - `10`：密码错误或 vault.meta 损坏 → 重试/导入 Armor Key 两个选项。
  - `11`：链断裂/回滚 → 停止写入，引导 `doctor --chain`，不要自动修复。
  - `12`：损坏 → 停止，引导 `verify --deep`；doctor 的 FAIL 也走这里。
  - `13`：不完整 → 等待云同步/重试；若用户显式选择渐进恢复，展示缺失 pack 列表。
  - `14`：空间不足 → 清理/换目标。
  - `20`：锁 → 等待/修复；区分控制锁与 TargetDir 锁。
  - `21`：不支持的内容 → 调整排除/参数。
  - `130`：被取消（macOS 实测）→ 进入“修复写锁”状态。Windows 的 `TerminateProcess` 不保证返回 130，以“子进程已终止 + 锁检查”为准，不要只认 130。
  - `1`：未分类 → 收集诊断，提示反馈。

### 4.4 取消与修复状态机

```text
idle → running → (success | failed | interrupted)
interrupted → check-locks → (repair-needed | recovered)
repair-needed → 用户确认 → 清理目标锁/控制锁 → retry
```

- 用户点取消：先发一次温和终止（macOS SIGTERM；Windows 上 Dart 的 `kill` 是 TerminateProcess），等待 5 秒，仍未退出再强杀。
- 结束后检查：控制锁是否可获取、`.eimmortal.lock` 是否存在、stderr 是否出现 E130（Windows 可能没有 130，以进程终止 + 锁状态为准）。
- 不要静默删锁。弹窗说明“上一次备份被中断，写锁可能仍在；确认没有其他 eimmortal 进程后修复”，要求用户明确确认。
- 上游如果实现优雅取消（context 取消 + defer 释放锁），GUI 就只需要“重试”；这是推荐的 P0 改动。

---

## 5. UI 框架选型：Flutter vs Electron

> 说明：纯 Node.js 没有原生桌面壳；Node 桌面客户端实际上会落到 Electron（或 Tauri/Wails 等 WebView 壳）。本文按 Electron 评估，因为它是 Node 桌面端最主流、生态最完整的选择。

### 5.1 评分矩阵（针对这个产品，不是通用 benchmark）

权重按“备份/加密工具”的实际风险分配；分数 1–5。

| 维度 | 权重 | Flutter | Electron | 说明 |
|---|---:|---:|---:|---|
| 安全攻击面 | 20% | 5 | 3 | Flutter release 是 Dart AOT + 原生窗口，没有 DOM/JS/Chromium；Electron 需要 Chromium/Node 加固与持续升级 |
| 与 Go sidecar 的进程集成 | 15% | 4 | 5 | Electron 有 `windowsHide`、额外 stdio、AbortSignal；Flutter 只有 stdin/stdout/stderr/kill，但 `--password-fd 0` 已够用，Windows 可用 GUI 子系统变体补 |
| macOS/Windows 覆盖与构建可靠性 | 15% | 4 | 5 | Electron 内建 universal macOS、可跨构建 Windows 安装包；Flutter Windows 必须在 Windows 上构建，Intel macOS 官方在退场 |
| 打包/签名/自动更新 | 15% | 3 | 5 | Electron Builder/Updater 成熟；Flutter 需要 Xcode/lipo/notarize + Sparkle/WinSparkle |
| UI/UX 与数据密集界面 | 15% | 5 | 4 | 两者都能做；Flutter 的表格/树/进度/主题一致性好，Electron 的 Web 生态更大 |
| 体积/常驻内存/启动 | 10% | 5 | 2 | Electron 携带 Chromium+Node，安装包和基线内存明显更大；Flutter 更轻 |
| 团队与迭代速度 | 10% | 4 | 4 | 工作区在 `code/flutter`、本机 Flutter 3.47 已装；若团队是 Web/TS 背景则 Electron 更快 |
| **加权总分** | 100% | **4.30** | **4.05** | 差距不大，说明这是“取舍”而不是“碾压” |

### 5.2 为什么仍然选 Flutter

1. **安全边界更简单**：这是一个处理主密码和加密备份的工具。Flutter 发布产物没有浏览器内核、没有远程页面、没有 Node 运行时；攻击面主要是 Flutter engine + 少量插件。Electron 当然可以加固（`contextIsolation`、`sandbox`、`nodeIntegration: false`、CSP、IPC 校验），但这是一套需要持续维护的安全配置，且 Chromium 的安全更新节奏会变成你的发布节奏。
2. **体积/内存更符合“本地工具”定位**：Electron 的 Chromium/Node 基线很重；虽然 1.1 GB 的 Argon2 峰值才是大头，但它是瞬时的，UI 基线内存是常驻的。8 GB 机器上，轻量 UI + 瞬时子进程峰值，比重型 UI + 峰值更稳。需要说明：**体积/内存不是决定性因素**——1.1 GB 峰值双方都要承担；Flutter 的主要优势是安全边界和依赖面，不是省几百 MB。
3. **Flutter 桌面端已足够成熟**：官方支持 Windows 10/11（x64/arm64）与 macOS 12–27（x64/arm64），本机是 Flutter 3.47.5 / Dart 3.13.4。备份管理器需要的表格、树、表单、进度、文件选择、托盘、窗口管理都有成熟方案。
4. **进程集成的缺口有明确解**：
   - 密码：`--password-fd 0` 已被实测；`init` 不要求二次确认。
   - Windows 控制台窗口：Dart `Process.start` 没有 `windowsHide`，但可以给 GUI 单独构建 `-H windowsgui` 的 sidecar（已实测能产出 GUI 子系统 PE），stdio 管道仍需在 Windows 上验证；不行就加一个很小的原生启动插件。
   - macOS universal：sidecar 用 `lipo` 已验证；App 本身可以分别出 arm64/x64 两个 DMG，避免 Flutter universal 的工具链摩擦。
5. **单语言、少依赖**：Dart + 少量 pub 包，UI 与进程适配层同语言；不需要同时维护 TypeScript/React/Node 主进程/预加载脚本/打包配置。对一个小型桌面工具，这是实打实的维护成本差异。

### 5.3 Electron 在哪些点上更强，什么时候应改选

Electron 不是错误答案，它在以下场景明显更合适：

- **必须一个 universal macOS 安装包**，且不想在 CI 里折腾 Xcode `ARCHS`/lipo；
- **必须开箱即用的静默自动更新**（`electron-updater` 比 Flutter 的 Sparkle/WinSparkle 方案成熟）；
- **团队是 Web/TypeScript 背景**，React 组件和 Web 生态能显著加快 UI；
- **需要 `windowsHide`/额外 FD/更细的进程控制**，不想为 Flutter 写原生启动插件；
- **可以接受 Chromium 的包体、内存和更新节奏**。

如果出现以下任一硬约束，建议重新评估并改选 Electron：

1. macOS 必须长期同时支持 Intel + Apple Silicon，且只发一个 universal 包；
2. v1 就必须有静默自动更新；
3. 团队没有 Flutter/Dart 经验，但有成熟 React/Electron 经验；
4. Windows 上无法接受 GUI 子系统 sidecar 或原生启动插件的验证成本。

### 5.4 不作为首选的其它组合

- **Node.js 纯服务 + 浏览器打开**：不是桌面客户端，没有原生窗口/托盘/单实例，且本地 HTTP 端口增加攻击面。
- **Tauri**：Rust + WebView2，体积小，但仍要处理 WebView 运行时，且不在本次 Flutter/Node 的候选范围内。
- **Wails**：Go + WebView，能把核心直接编进同一进程，但这会把 1.1 GB Argon2 和崩溃风险带回 UI 进程，也把 UI 绑在 Go 上；与“薄客户端 + 稳定核心”的方向相反。
- **SwiftUI + WinUI 原生双端**：系统集成/TCC 最稳，但两份 UI、两套团队/构建，和“单代码库覆盖 macOS+Windows”的目标冲突。除非 TCC 证明 sidecar 不可行且必须原生，不选。
- **Flutter + go-flutter**：非官方桌面 embedder，维护状态不适合新项目；用官方 Flutter desktop。

---

## 6. 推荐架构

### 6.1 分层

```text
┌────────────────────────────────────────────────────────────┐
│ Flutter UI (Dart, macOS/Windows)                            │
│  onboarding / unlock / dashboard / backup / history /      │
│  restore / verify / settings / logs                         │
├────────────────────────────────────────────────────────────┤
│ Application layer                                           │
│  - CommandQueue（全局单飞）                                 │
│  - Operation state machine（idle/running/interrupted/...）  │
│  - Command-specific result mapping（JSON + exit code）      │
├────────────────────────────────────────────────────────────┤
│ CoreGateway (Dart)                                          │
│  - resolve bundled sidecar path + verify SHA-256/signature  │
│  - build args, write password to stdin, stream stderr       │
│  - capture stdout JSON, map exit codes, cancel/kill         │
├────────────────────────────────────────────────────────────┤
│ eimmortal sidecar (Go, signed, pinned)                      │
│  --config <gui config> --json --password-fd 0 ...           │
├────────────────────────────────────────────────────────────┤
│ vault/ (control plane)        TargetDir/ (ciphertext)       │
└────────────────────────────────────────────────────────────┘
```

关键原则：**UI 不实现任何加密、索引、pack/journal 逻辑**。它只负责收集参数、展示结果、解释错误、串行调度。所有数据事实以 CLI 的 JSON 为准。

### 6.2 建议的 Flutter 技术栈

| 用途 | 选择 | 备注 |
|---|---|---|
| 状态管理 | Riverpod（或 Bloc） | 单飞队列和异步操作状态清晰 |
| 路由 | go_router | 桌面多页面/深链接 |
| 数据模型 | 手写 `fromJson` 或 `freezed` + `json_serializable` | CLI JSON 有 `null` 数组、可选字段；不要过度依赖代码生成 |
| 文件选择 | `file_selector` | 官方插件，macOS/Windows 支持 |
| 路径/应用目录 | `path_provider` + `path` | 配置/日志/缓存 |
| 安全存储 | `flutter_secure_storage` | 仅用于“记住密码”可选功能/非核心设置；默认不存主密码 |
| 窗口/托盘 | `window_manager`、`tray_manager` | 单实例、关闭确认、托盘（若做后台） |
| 启动项 | `launch_at_startup` | 可选，v1 可不做 |
| 日志 | `logging` + 内存环形缓冲 | 默认不落盘，避免明文路径/消息 |
| 国际化 | `intl` / ARB | v1 中文；CLI 原始错误仍是中文 |
| 测试 | `flutter_test` + `integration_test` | 加真实 sidecar 的端到端测试 |

依赖原则：能少则少。每个插件都是原生代码和供应链风险；尤其是文件系统/进程/安全存储相关插件，锁版本并审查。`flutter_secure_storage` 在 Windows 需要 C++ ATL；macOS Keychain 要按插件文档处理 entitlements，避免不必要的 `keychain-access-groups` 导致分发签名复杂化。

### 6.3 配置与数据布局

- **核心配置**：沿用 CLI 的 `config.toml` 语义，由 GUI 生成/维护，权限 0600；GUI 通过 `--config` 指向 profile 的配置文件。若用户已有 CLI 配置，先读取/备份，只改白名单字段；高级用户可以选择“使用现有配置”，GUI 不做全量重写。注意 Dart 没有 chmod API，macOS 上需用 `Process.run('/bin/chmod', ['600', path])` 或原生 FFI 设置权限；否则 CLI 会以 E2 拒绝 0644 的配置。Windows 跳过 mode 检查，但仍应放在用户目录。配置内容用 TOML writer 生成，不要手拼字符串；Windows 路径的反斜杠/引号要正确转义。
- **控制平面**：默认 `~/.eimmortal/eimmortal-vault`；GUI 发现已有安装时优先复用，不复制 `state.db`。onboarding 要拒绝把 vault 放进 TargetDir 或已知同步目录，并用 `doctor` 复检；staging 必须与 TargetDir 同卷。
- **GUI 设置**：窗口状态、最近操作、source root 绑定、更新检查等，放在应用自己的目录（如 macOS `~/Library/Application Support/EncryImmortals/`、Windows `%APPDATA%\EncryImmortals\`），不要写进 TargetDir。
- **不要持久化**：`log`/`show`/`ls` 的输出包含明文文件名/提交消息；默认只放内存。若要做本地缓存，必须用 OS 级密钥加密，且默认关闭。
- **不要记录**：主密码、Armor Key、密码文件路径、完整文件列表。诊断日志默认只保留错误码、计数、版本。
- **多 profile**：v1 单 profile；数据结构预留 `profileId`，但 UI 不暴露多开，避免控制锁/源根混乱。
- **macOS 首次设置**：默认 `scan.ignore_xattr = true`，并在 UI 写明代价（xattr/ACL 不会还原）；否则 `com.apple.provenance` 一类属性会让 backup 以 E21 失败。
- **只暴露已实现配置**：`concurrency.*`、`checkpoint.*`、`verify.auto_strict_every` 当前未生效（`config.example.toml` 标注“未实现”）；设置页不要把它们做成可编辑开关，或明确置灰说明。`--jobs` 也未实现，不要暴露。

### 6.4 关键流程（MVP）

1. **创建新库**：选源目录 → 选 TargetDir → 输入主密码两次 → `init`（stdin 密码）→ `export-key --json` 拿 Armor Key → 展示一次性备份提示 → 写入 profile（source root 固定）。
2. **加入已有库**：选 TargetDir → `init --join <TargetDir>`（无密码）→ 输入 Armor Key（stdin）→ `import-key` → 输入主密码 → `log --json` 验证解锁 → `doctor --chain` / `verify --size` → 可恢复。
3. **解锁**：`log --json` 作为密码探针；成功后在内存中保留密码（仅当前会话），失败 E10 重试/导入 Key。随后用 `status --chain` 刷新健康度；若 warnings 含解锁/链/锚点问题，或 `verified=false`，显示“降级/未验证”，不要给绿色对勾；普通提醒（如“从未做恢复演练”）单独展示。
4. **备份**：可选 `--dry-run` → 展示计数/文本估计（JSON 暂无 estimated 字段）→ 正式 `backup --json` → 流式 stderr 进度 + 最终 JSON → `truncated` 时提示“继续剩余部分”；成功页要明确“本地提交完成，云端同步由网盘客户端负责”。
5. **历史**：`log --json` → 选中 seq → `show <seq> --json`；文件树用 `ls --at <seq> [prefix] --json` 按目录懒加载。
6. **恢复**：选快照/目标空目录 → **先 `doctor --chain`**（防回滚）→ `restore --list-packs --json` 看缺失 → 可选 `--dry-run` → 正式恢复 → 处理 E13 部分恢复；等待同步用 `--wait-for-packs`，渐进恢复用 `--skip-missing-packs`，两者都要用户显式选择。
7. **校验**：`verify --sample N --json` / `doctor --chain --json`；展示 PASS/WARN/FAIL 表格与下一步。
8. **Key**：`export-key --json` 展示/复制（警告剪贴板风险）；`import-key` 走 stdin；永不写日志。

### 6.5 安全设计（客户端特有）

1. **sidecar 完整性**：sidecar 必须在签名后的 app bundle/安装目录内；构建期把其 SHA-256 写进 Dart 常量，启动时校验；生产构建不允许用户指定任意核心路径（开发模式可开，但显式警告）。macOS 用 Developer ID 签名 + notarization；Windows 用 Authenticode 签名。仅靠“放在 Resources 里”不够。
2. **密码生命周期**：密码只存在于内存和 stdin 管道；不写 argv/env/文件/日志；不用 `--password-file` 做交互操作。Dart String 无法可靠清零，尽量减少持有时间，退出/锁屏/超时后清空。
3. **“记住密码”默认关闭**：如做，使用 macOS Keychain / Windows Credential Manager，并明确告知“本机同用户会话可读取”，不要把“记住密码”包装成“更安全”。
4. **Armor Key**：`init` 的 stdout 包含 Armor Key，捕获后立刻转成 UI 状态，绝不落盘/日志；复制到剪贴板要提示可能被云剪贴板/输入法记录；优先建议用户存入密码管理器。网关按命令标注 `sensitive`（`init`/`export-key`/`compact --new-identity`/`import-key`），通用日志器不得无差别打印子进程输出。
5. **不落明文缓存**：commit message、文件路径、目录树都是敏感信息；默认只在内存。日志默认不落盘；诊断导出需用户确认并脱敏。
6. **更新**：v1 只做“检查新版本 + 打开下载页”，不做静默自动更新；更新必须同时替换 UI 和 sidecar，不能让两者版本漂移。所有更新包必须签名/校验；有命令运行时禁止更新/重启。
7. **危险操作**：`--break-lock`、`gc --prune-orphans --yes`、`compact`、`restore --overwrite always`、`--accept-data-loss` 全部要二次确认 + 明确影响范围；不要默认勾选。
8. **恢复前防回滚**：`restore` 自己不校验锚点，GUI 必须先 `doctor --chain`；FAIL 时禁止恢复，除非用户明确接受风险（且 UI 要写清楚“可能恢复到旧快照”）。
9. **单实例 + 退出保护**：防止两个 GUI 同时操作；退出时若有命令运行，先取消并等待，处理锁，再退出。
10. **供应链**：锁定 pub 依赖；审查进程/文件/安全存储插件；CI 构建产物校验；发布附 checksums。

### 6.6 打包与分发

**核心 sidecar 的来源**

- 在 UI 仓库放 git submodule：`third_party/encry-immortals`，固定到 tag（当前最新 `v0.1.5`）或一个明确 commit；不要跟 `main` 浮动。
- 用 `tool/build_core.dart`（跨平台）或 `scripts/build_core.sh`：
  - `CGO_ENABLED=0 GOOS=... GOARCH=... go build -trimpath -ldflags "-s -w -X main.version=<tag>"`；
  - macOS：分别出 arm64/amd64，`lipo -create` 成 universal；
  - Windows：出 `eimmortal.exe`（console）和 `eimmortal-gui.exe`（`-H windowsgui`，给 GUI 用），二者同源；
  - 校验 `eimmortal version` 输出与 tag 一致；计算 SHA-256 生成 Dart 常量。
- 备选：直接下载核心的 GitHub Release 资产 + `checksums.txt`，避免 UI CI 依赖 Go；但开发期仍建议 submodule，便于打上游补丁。两者不要混用同一个文件名。

**macOS**

- `flutter build macos --release`，然后 Xcode 签名/归档；sidecar 放在 `Contents/Resources/bin/`（或 `Contents/MacOS/`），用 `codesign --options runtime` 单独签，再签整个 app；`notarytool` 提交，stapling。
- 不建议 Mac App Store / App Sandbox：备份工具需要读取用户选择的任意目录，沙箱 + security-scoped bookmark + 子进程继承会让问题复杂化；直接 Developer ID 分发。
- Intel：Flutter 官方已在退场 Intel macOS。v1 建议 Apple Silicon 为主，x64 单独构建/单独 DMG；如果必须长期支持 Intel，把这一点作为改选 Electron 的触发条件。
- Full Disk Access：读取 `~/Documents`/`~/Desktop` 等需要 FDA；首次引导用户到系统设置授权，并说明为什么需要。

**Windows**

- `flutter build windows --release` 必须在 Windows 上做（Visual Studio + Desktop development with C++）；GitHub Actions `windows-latest` 解决。
- sidecar 放 `data\bin\eimmortal.exe` 或 app 同级的 `bin\`；用 CMake install/安装器复制，不要运行时从 assets 解压（杀软/权限/签名问题）。
- 控制台窗口：优先用 `-H windowsgui` 的 sidecar；若管道 stdio 在 Windows 上不工作，写一个很小的原生启动插件用 `CreateProcessW` + `CREATE_NO_WINDOW`，保留 console 版 CLI 给终端用户。
- 安装器：Inno Setup 或 MSIX。Inno 更简单、对 sidecar/文件系统更透明；MSIX 有虚拟化和后台任务限制。二者都要 Authenticode 签名，时间戳。
- 长路径/大小写冲突/xattr 等：CLI 会 fail-fast E21；GUI 在路径选择时提前提示，不要等备份跑一半才报错。

**CI**

- macOS arm64 runner 构建 arm64 + sidecar arm64；macOS Intel runner 构建 x64（若支持）；`windows-latest` 构建 Windows x64 + sidecar GUI 版。GitHub 的 [`macos-14` 镜像将于 2026-11-02 退役](https://github.blog/changelog/2026-10-01-github-actions-macos-14-runner-image-retirement/)，CI 里不要写死它，按当前可用标签选择。
- Go 构建可单独在 `ubuntu-latest` 交叉出 darwin/windows 二进制，作为快速校验；但 Flutter 壳必须对应宿主构建。
- 缓存 pub/Go；签名/公证密钥放 secrets；发布产物附 SHA-256 和版本清单（app version + core version）。

### 6.7 上游改动清单（按优先级）

**P0（Windows 发布阻塞项 / 取消体验）**

1. **Windows 控制锁改成真正的 OS 文件锁**：用 `golang.org/x/sys/windows` 的 `LockFileEx`（仓库已依赖 x/sys），进程退出自动释放；或者至少在锁文件里写 PID/启动时间并提供安全的 stale 检测。当前 `O_EXCL` 标记文件在崩溃后必须手工删除，GUI 很难可靠修复。
2. **优雅取消/锁清理**：`main.go` 现在收到 SIGTERM 直接 `os.Exit(130)`，defer 不执行，TargetDir 锁留下。改成 context 取消，让 pipeline 走正常清理；或提供 `eimmortal lock status/repair` 命令。GUI 的取消按钮依赖这个。

**P1（体验/兼容性）**

3. **结构化进度**：`--events=ndjson` 或 `--progress=json`，至少包含 `phase / done_files / total_files / done_bytes / total_bytes / current / speed`；保留现有 stderr 人类输出。GUI 不应该靠正则解析中文。
4. **`init` / `import-key` 的 JSON 输出**：至少 `init --json` 返回 `vault_id / kdf / armor / warnings`；`import-key --json` 返回 `vault_id / target_dir`。避免 GUI 解析人类文本/抓 Armor Key。
5. `backup --dry-run --json` 补 `estimated_packs` / `estimated_bytes`。
6. 所有 JSON 输出加 `schema` 字段；错误加结构化错误对象（code/message/next），或在 `--json` 下把错误 JSON 写 stderr。
7. `restore` 实现锚点校验（或至少把 `doctor --chain` 的检查内置），并补 `--anchor` / `--i-accept-unverified` 的实际语义（当前 spec 有、代码没有）。
8. `status --chain` 在密码错误/链校验失败时应返回非零（或明确 `degraded: true`），不要只加 warning 返回 0。
9. `ls`/`show`/`log` 的分页/上限（大快照/长历史）。
10. 单源根元数据：在 `vault.meta` 记录 source root（格式变更需慎重），让 GUI/多机都能校验。

**P2（可选）**

11. `--password-command` 或系统钥匙串密码源，支持真正安全的无人值守定时备份（替代 0600 明文密码文件）。
12. 自动更新/版本协商；多 vault/profile。
13. `cat` 的流式文件导出（避免一次性进内存）。

---

## 7. 里程碑（粗略，不是承诺）

| 阶段 | 内容 | 估算 |
|---|---|---|
| M0 · Spike | sidecar 适配层 + init/backup/log/restore 垂直切片；Windows GUI 子系统 stdio、控制锁、取消；macOS 签名/公证最小样例 | 2–3 天 |
| M1 · MVP | onboarding（创建/加入/导入 Key）、解锁、仪表盘、备份（dry-run/进度/结果）、历史、恢复（list-packs/校验）、验证/doctor、设置、Key 导出 | 2–3 周 |
| M2 · Hardening | 取消/修复、结构化进度、Windows 安装器/签名、macOS 公证、单实例/退出保护、集成测试矩阵、诊断日志 | 2–3 周 |
| M3 · 可选 | 定时备份（钥匙串/`--password-command`）、自动更新、多 profile、托盘后台 | 按需 |

M1 之前不要做“漂亮但不可靠”的动画/图表；先把错误码、锁、恢复安全跑通。

---

## 8. 风险与必须先验证的未知项

| 风险 | 影响 | 缓解 |
|---|---|---|
| Windows 控制锁是标记文件 | 崩溃后所有命令 E20，用户必须手工删文件 | 上游 P0 改 `LockFileEx`；GUI 提供“修复锁”流程并明确风险 |
| 取消留下 TargetDir 锁 | 下次备份 E20；用户以为数据坏了 | 上游 P0 优雅取消；GUI 中断状态 + 修复确认；绝不静默删锁 |
| 1.1 GB Argon2 峰值 | 8 GB 机器上短时内存压力；并发会 OOM | 单飞队列；不并发；subprocess 隔离；UI 提示“正在解锁” |
| Flutter macOS Intel 退场/universal 摩擦 | 无法长期单包支持 Intel | Apple Silicon 优先；x64 单独构建；把 universal 作为改选 Electron 的触发条件 |
| Windows 构建必须 Windows 宿主 | 无 Windows 机器/CI 时无法出包 | GitHub Actions `windows-latest`；或 Windows VM |
| Dart 无 `windowsHide` | 可能闪控制台窗口 | GUI 子系统 sidecar（已验证可构建，运行期待验证）；备选原生启动插件 |
| macOS TCC/FDA 不覆盖 sidecar | 读不到 `~/Documents` 等目录，备份失败 | M0 用签名 app 验证子进程归属；若 TCC 拒绝，重评 FFI/原生方案，不要只让用户“再授权一次” |
| sidecar 被替换 | 可窃取 stdin 中的主密码 | 签名 + 固定 SHA-256 + 不允许自定义路径；更新包签名 |
| 杀软/SmartScreen 误报 | 安装/运行被拦截，用户流失 | 签名（EV/OV 证书）、提交微软误报、发布 checksums、安装器不要静默下载 |
| 自动更新不成熟 | 用户长期停留在旧版 | v1 只做检查+下载页；M3 再评估 Sparkle/WinSparkle（`auto_updater` 维护频率一般） |
| 源根被改 | 链语义破坏，后续 E12 | profile 固定 source root；换源必须新建 vault；UI 强提示 |
| 无 LICENSE | 无法合法分发 | 发布前选许可证（核心 README 已注明 All rights reserved） |
| JSON/CLI 契约漂移 | UI 解析失败/误判 | 固定 core 版本；[集成契约](integration-contract.md) + 集成测试；升级前 diff `--help`/JSON |
| 大快照/长历史 | `ls`/`show`/`log` 输出过大 | v1 用 `ls <prefix>` 懒加载；上游 P1 分页；UI 限流 |
| 无人值守定时 | 没有安全的密码来源 | v1 不做；M3 用 Keychain/DPAPI 或 `--password-command`；不要默认写明文密码文件 |

**Spike（2–3 天）必须先回答的 3 个问题**

1. **Windows**：GUI 子系统 `-H windowsgui` 的 sidecar 在 Flutter `Process.start` 下 stdin/stdout 是否正常？控制锁崩溃残留能否在 GUI 里安全修复？取消后锁状态如何呈现？
2. **macOS**：签名 + notarization 后的 app 内 sidecar 能否正常执行、通过 Gatekeeper？TCC/Full Disk Access 对 sidecar 的归属是否稳定？arm64/x64 两种构建是否都能跑通？
3. **产物**：sidecar 的 SHA-256/签名校验、单实例、命令队列、JSON+退出码映射能否在一个最小 vertical slice 里稳定工作（init → backup → log → restore → verify）？

---

## 9. 需要你拍板的产品决策

1. **定时备份**：v1 是否只需要“打开 App 时手动/应用内定时”，还是必须无人值守（关闭 App 也跑）？后者需要钥匙串/DPAPI 或 `--password-command`，并接受“本机同用户可解密”的风险。
2. **macOS Intel**：是否必须长期支持 Intel？如果只要求 Apple Silicon，Flutter 方案风险很低；如果必须长期双架构单包，建议改选 Electron。
3. **Windows 构建**：是否有 Windows 机器/CI？没有的话先配 GitHub Actions `windows-latest`，否则 Windows 支持只能停留在“代码层面”。
4. **上游改动**：是否接受先向 `encry-immortals` 提 PR（P0：Windows 锁、优雅取消；P1：结构化进度、init/import JSON）？如果不接受，GUI 也能做，但要接受修复流程和解析人类输出的脆弱性。
5. **分发渠道**：官网 DMG/EXE（推荐，需 Apple Developer/Windows 代码签名证书）还是应用商店？商店沙箱会显著增加文件访问/子进程的复杂度。
6. **多 vault/profile**：v1 是否只需要一个活动库？多库会放大锁、源根、配置和 UI 复杂度。
7. **许可证**：核心和 UI 仓库目前都没有 LICENSE；对外分发前必须选一个（MIT/Apache-2.0/AGPL 等），否则默认 All rights reserved。

---

## 10. 参考

**本地代码与文档**

- CLI 契约：[`internal/cli/cli.go`](https://github.com/tangthinker/encry-immortals/blob/main/internal/cli/cli.go)、[`docs/spec/10-cli-and-config.md`](https://github.com/tangthinker/encry-immortals/blob/main/docs/spec/10-cli-and-config.md)
- 密码输入：[`internal/cli/password.go`](https://github.com/tangthinker/encry-immortals/blob/main/internal/cli/password.go)
- 退出码：[`internal/apexerr/errors.go`](https://github.com/tangthinker/encry-immortals/blob/main/internal/apexerr/errors.go)
- 锁：[`internal/lock/control_unix.go`](https://github.com/tangthinker/encry-immortals/blob/main/internal/lock/control_unix.go)、[`internal/lock/control_other.go`](https://github.com/tangthinker/encry-immortals/blob/main/internal/lock/control_other.go)
- 信号处理：[`cmd/eimmortal/main.go`](https://github.com/tangthinker/encry-immortals/blob/main/cmd/eimmortal/main.go)
- 构建/发布：[`scripts/release-build.sh`](https://github.com/tangthinker/encry-immortals/blob/main/scripts/release-build.sh)、[`.github/workflows/ci.yml`](https://github.com/tangthinker/encry-immortals/blob/main/.github/workflows/ci.yml)
- 安全边界：[`docs/security.md`](https://github.com/tangthinker/encry-immortals/blob/main/docs/security.md)
- 定时/密码文件：[`docs/operations.md`](https://github.com/tangthinker/encry-immortals/blob/main/docs/operations.md)

**外部资料**

- Flutter 支持平台（Windows 10/11、macOS 12–27、Intel 退场提示）：<https://docs.flutter.dev/reference/supported-platforms>
- Flutter Windows 环境（Visual Studio C++）：<https://docs.flutter.dev/platform-integration/windows/setup>
- Flutter macOS 构建/签名/沙箱：<https://docs.flutter.dev/platform-integration/macos/building>
- Dart `Process`（仅 stdin/stdout/stderr、kill、exitCode）：<https://api.dart.dev/stable/latest/dart-io/Process-class.html>
- Node `child_process`（`windowsHide`、stdio、AbortSignal）：<https://nodejs.org/api/child_process.html>
- electron-builder 架构/universal/跨平台构建：<https://www.electron.build/docs/architecture/>
- Electron 安全清单：<https://www.electronjs.org/docs/latest/tutorial/security>
- Flutter secure storage（macOS Keychain / Windows）：<https://pub.dev/packages/flutter_secure_storage>
- Flutter auto_updater（Sparkle/WinSparkle）：<https://pub.dev/packages/auto_updater>
- Go internal 包规则：<https://go.dev/doc/go1.4#internalpackages>
