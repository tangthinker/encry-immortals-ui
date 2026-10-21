# 客户端 ↔ 核心 CLI 集成契约

> 配套文档：[tech-selection.md](tech-selection.md) · 状态：Proposed
>
> 目的：把 GUI 可以依赖的 CLI 行为冻结下来，避免 UI 直接解析人类文本、误判退出码或在 Windows 上被锁卡死。
>
> 基线：本地 `main` `32889e1` 构建出的 `bin/eimmortal 0.1.0-dev`（写作时 main 已到 `340cade`，两者之间仅 README 变更；最新 tag 为 `v0.1.5`）+ 本文实测。**发布时必须固定到 tag/commit，并用该产物重跑第 8 节契约测试**；不要把本文的实测当成 v0.1.5 的承诺。

---

## 1. 调用模板

```text
<sidecar> --config <config.toml> --json --password-fd 0 <command> [args...]
```

- `--config`、`--json`、`--password-fd` 是全局参数，可放在命令前后；GUI 统一放在命令前。
- `--vault <dir>` 可选；GUI 通常让 `config.toml` 的 `[vault] dir` 决定。
- 参数用数组传递，不经过 shell；路径使用绝对路径。
- `cwd` 设为用户主目录或应用数据目录均可；所有路径显式传绝对路径，避免相对路径歧义。
- 环境变量：保留 `PATH`、`HOME`/`USERPROFILE`、`TMPDIR`/`TEMP`、`LANG`/`LC_ALL`、Windows 的 `SystemRoot`、`APPDATA`、`LOCALAPPDATA`。不要传任何密码相关环境变量。
- 不要使用 `--password-file` 做交互式操作；它只用于用户明确开启的无人值守场景。
- 配置文件在 POSIX 上必须是 0600。Dart 没有 chmod API：用 `Process.run('/bin/chmod', ['600', path])` 或原生 FFI；否则 CLI 以 E2 拒绝 0644 的配置。Windows 跳过 mode 检查，但应放在用户目录/受 ACL 保护的位置。

---

## 2. 命令能力矩阵

“密码”指是否需要通过 stdin 提供主密码；“JSON”指 stdout 是否是可解析的 JSON（错误时可能为空）；“非零但有 JSON”表示必须保留 stdout。

| 命令 | JSON | 密码 | stdin | 写 TargetDir | 写控制平面 | 备注 |
|---|---|---:|---|---:|---:|---|
| `version` | 文本 | 否 | 否 | 否 | 否 | 解析 `eimmortal <ver>` |
| `help` / `--help` | 文本 | 否 | 否 | 否 | 否 | 只用于诊断 |
| `status` | 是 | 否 | 否 | 否 | 否（`--clear-unverified` 时是） | 未解锁时 `referenced=0`、`logical_source=0`，不可当真 |
| `status --chain` | 是 | 是 | 否 | 否 | 否 | 密码错误/链失败可能只加 warning 并 exit 0，且 `verified` 仍可能为 true；以 `warnings` 为准，不要只看 `verified` |
| `log` | 是 | 是 | 否 | 否 | 否 | 可作解锁探针（错误密码 → E10） |
| `show <seq>` | 是 | 是 | 否 | 否 | 否 | 大提交的 `ops` 可能很大 |
| `ls [prefix] --at <seq>` | 是 | 是 | 否 | 否 | 否 | 用 prefix 做目录懒加载；大快照避免全量 |
| `cat <path> --at <seq>` | **原始字节** | 是 | 否 | 否 | 否 | 不是 JSON；v1 不做预览 |
| `manifest <pack>` | 是 | 是 | 否 | 否 | 否 | 高级功能 |
| `backup --source <dir>` | 是 | 是 | 否 | 是 | 是 | `--dry-run` JSON 缺 estimated 字段 |
| `restore <dest>` | 是 | 是 | 否 | 否（写 dest） | 否（只打开） | 缺 pack 时先 JSON 后 E13；不做锚点校验 |
| `restore --list-packs` | 是（数组） | 是 | 否 | 否 | 是 | 用于渐进恢复 |
| `verify` | 是 | 是 | 否 | 否 | 否 | 缺 pack → E13；损坏 → E12；JSON 已输出 |
| `doctor` | 是（数组） | 否（结构检查） | 否 | 否 | 否 | `--chain` 才要密码；有 FAIL → E12，JSON 已输出 |
| `init` | 否 | 是 | 否 | 否 | 是 | stdout 含 Armor Key；不要落日志 |
| `init --join <target>` | 否 | 否 | 否 | 否 | 是 | 写 `pending-target` |
| `import-key` | 否 | 否 | **Armor Key** | 否 | 是 | 成功看 exit 0；用 `export-key`/`status` 复核 |
| `export-key` | 是 | 否* | 否 | 否 | 是 | 实现不要求密码；会更新导出时间 |
| `gc` | 是 | 是 | 否 | 可选 | 否 | 删除孤儿需 `--prune-orphans --yes`；高级 |
| `compact` | 是 | 是 | 否 | 是（新目录） | 可选（`--new-vault`） | `--new-identity` 时 JSON 含 `armor_key`，敏感 |
| `rebuild-state` | 否 | 是 | 否 | 否 | 是（重置 state.db） | 会重建锚点；高级/危险 |
| `note <msg>` | 否 | 是 | 否 | 是 | 否 | 无 JSON；高级 |

\* `export-key` 的文档表格写“需要密码”，但当前实现是 `openSession(g, false)`，不读密码。GUI 可以要求用户先解锁再导出，但不要依赖 CLI 的密码校验。

**stdin 是单一通道**：需要密码的命令只收密码；`import-key` 只收 Armor Key；没有命令同时需要两者。`--password-fd 0` 不会和 `import-key` 冲突，但网关必须按命令选择写入内容，不要给不需要 stdin 的命令乱写。

### 2.1 最小 MVP 命令集

`version`、`status`、`log`、`show`、`ls`、`backup`、`restore`、`verify`、`doctor`、`init`、`init --join`、`import-key`、`export-key`。

`cat`、`manifest`、`gc`、`compact`、`rebuild-state`、`note` 放到“高级/暂不支持”，避免 v1 的破坏性操作面。

---

## 3. 密码与 stdin

### 3.1 交互式操作

- 统一使用 `--password-fd 0`。
- 写 `password + "\n"`，随后 `stdin.close()`。
- 不写 `--password-file`，不写环境变量，不把密码拼进 argv。
- 密码不能包含换行；CLI 按行读取。GUI 应在输入校验中拒绝 `\n`/`\r`，并限制长度（CLI 上限 4096 字节）。
- 空密码由 CLI 拒绝（E2）；初始化时弱密码会提示，只有显式 `--accept-weak-password` 才继续。
- `init` 在非交互密码源下会跳过二次确认；GUI 自己负责“输入两次”的 UI 校验。

### 3.2 需要 Armor Key 的命令

- `import-key` 从 stdin 读取 Armor Key（`io.ReadAll`），不需要密码。
- 不要把 Armor Key 放进 argv（会出现在进程列表）。
- `init` 的 stdout 同时含 Armor Key 的单行版和分组版；GUI 应捕获到内存后立即转为 UI 状态，**绝不写日志/临时文件**。更稳的做法是 init 成功后调用 `export-key --json`，只解析 JSON 的 `armor`/`grouped`。

**敏感命令标注**：`init`、`export-key`、`compact --new-identity`、`import-key` 的 stdout/stdin 含 Armor Key 或密钥材料。网关必须给这些命令打 `sensitive=true`：不记录原始 stdout/stdin，不写入诊断包/崩溃报告，只在内存中交给 UI；通用日志器不能无差别打印子进程输出。

### 3.3 为什么不用 `--password-fd 3`

`--password-fd` 支持任意 fd，但 Dart 的 `Process.start` 不能给子进程传额外 fd；`--password-fd 0` 用 stdin 管道即可。Electron 可以传额外 fd，但没有必要。

---

## 4. 结果、退出码与 JSON

### 4.1 统一结果对象

```text
CoreResult {
  exitCode: int
  stdout: String        // UTF-8；可能是 JSON、文本或空
  stderr: String        // 人类日志/错误
  json: Object?         // 命令支持 JSON 且 stdout 可解析时
}
```

处理顺序：

1. 并发读取 stdout/stderr，避免管道阻塞（不要用 `Process.run` 等全部结束再读；Dart 文档明确警告管道容量）。
2. 等 `exitCode`。
3. 如果命令属于“JSON 能力”且 stdout 非空，尝试解析；**即使 exitCode != 0 也解析**（doctor/restore/verify 会先输出 JSON）。
4. 如果 exitCode == 0 但 JSON 解析失败：视为协议错误，展示 stderr + 诊断，不要静默当成功。
5. 如果 stdout 为空：用 stderr 和退出码映射错误。
6. 对 `init`/`import-key`/`rebuild-state`/`note` 不做 JSON 解析；用退出码 + 后续查询确认。

### 4.2 退出码语义（稳定契约）

| 码 | 含义 | GUI 行为 |
|---:|---|---|
| 0 | 成功（含 `no changes`） | 渲染结果；注意 `status --chain` 的 warnings |
| 1 | 未分类 | 展示 stderr；收集诊断；不要自动重试写操作 |
| 2 | 用法/参数/配置 | 引导设置；展示可执行的修正建议 |
| 10 | 密码错误或 vault.meta 损坏 | 重试密码 / 导入 Armor Key；不要断言“密码一定错” |
| 11 | 链断裂/回滚/截断 | 停止写入；`doctor --chain`；禁止自动修复 |
| 12 | 数据损坏/格式非法 | 停止；`verify --deep`；保留证据 |
| 13 | 数据不完整（pack 缺失） | 等待同步/重试；渐进恢复需用户明确选择 |
| 14 | 空间不足 | 清理/换目标后重试 |
| 20 | 锁被占用 | 等待/修复；区分控制锁与 TargetDir 锁 |
| 21 | 不支持的内容 | 调整排除/参数；解释硬链接/xattr/稀疏/超长路径等 |
| 130 | 被 SIGINT/SIGTERM 中断（macOS 实测） | 进入“中断/修复锁”流程；幂等重跑。Windows 强杀可能不是 130 |

### 4.3 每个命令的结果要点

- **backup**：`changed=false` 是成功；`truncated=true` 不是失败，提示继续剩余部分；`skipped` 是读取期间被修改而跳过的文件；`seq=0` 表示没有提交。
- **restore**：先输出 JSON，再可能因 `incomplete` 返回 13；`missing_packs`/`missing_files` 要展示；`corrupt` 非空时还会返回 12。`skipped` 是 `--overwrite` 策略导致的跳过。
- **verify**：缺失 → 13，大小/抽样/深度失败 → 12，JSON 均已输出。`null` 数组表示空，不要当解析失败。
- **doctor**：JSON 数组，`status` 为 `PASS|WARN|FAIL|SKIP`；任一 FAIL → exit 12。`--chain` 的密码错误会表现为某个 check 的 FAIL，而不是 E10；GUI 先做解锁探针。
- **status**：`schema=1`；未解锁时 `packs.referenced=0`、`bytes.logical_source=0`，不要展示成“0 引用/0 逻辑大小”；`warnings` 要展示；`verified=false` 不代表一定被回滚，但必须提示。**密码错误/链失败时 `verified` 可能仍为 `true`**（它是解锁前按锚点算的），必须同时检查 warnings 是否含“未能取得主密码/无法解锁/链校验失败”。
- **init**：成功输出含 Armor Key；失败可能是已存在（E2）。成功后不要从 stdout 解析 key 的格式，直接 `export-key --json`。
- **import-key**：成功输出人类文本；用 `export-key --json` 或 `status --json` 复核 vault_id/target_dir。
- **export-key**：JSON `{armor, grouped}`；这是敏感信息，不落日志。
- **compact**：JSON 可能含 `armor_key`（`--new-identity`），敏感；`dropped` 非空时返回 13。v1 不图形化。

### 4.4 解锁探针

推荐用 `log --json` 作为“密码是否正确”的探针：

- 正确：exit 0，返回数组（可能为空）。
- 错误：exit 10，stdout 为空。
- 它同时拿到历史列表，避免多跑一次。

不要用 `status --chain` 做密码探针：密码错误时可能只是 warning 并 exit 0。

---

## 5. 进度与日志

### 5.1 现状

- 进度由 core 以人类可读中文写 stderr，约每秒一行，例如：
  `备份进度 1/3 文件 · 1.0 MiB/2.0 MiB（50%）· 写入均速 12.3 MiB/s · 当前 path/to/file`。
- 最终结果在 stdout JSON；进度不保证与最终 JSON 完全同步。
- 恢复、校验、compact 也有类似的人类进度。

### 5.2 客户端策略

- **v1**：把 stderr 当“日志流”展示；顶部用不确定进度条 + 当前阶段/最后一行；最终用 JSON 展示确定的结果。可选地用正则提取百分比用于视觉反馈，但**不能**用它判断成功/失败/剩余量。
- 正则只作为显示优化，解析失败就退回纯日志；不要因为一行格式变化而报错。
- UI 更新节流（例如 100 ms），日志用环形缓冲，避免每行触发整页重建。
- **P1 上游**：增加 `--events=ndjson`（或 `--progress=json`），输出结构化事件：
  `{type:"progress", phase:"write", done_files, total_files, done_bytes, total_bytes, current, speed_mib_s}`；
  以及 `{type:"log", level, message}`、`{type:"result"}`。保留现有 stderr 人类输出，保证向后兼容。
- 默认不把含文件路径的日志落盘；诊断导出需用户确认并脱敏。

---

## 6. 锁、并发与取消

### 6.1 控制锁

- 进入 `openSession` 的命令都会拿 `<vault>/lock`：Unix `flock`，Windows `O_EXCL` 标记文件。
- 因此**几乎所有命令都要串行**，包括 `status`、`export-key`、`doctor`。不要并发“备份 + 刷新状态”。
- GUI 单一命令队列；运行中禁用其他会拿锁的入口。
- 单实例应用锁，避免两个 GUI 操作同一个 vault。

### 6.2 TargetDir 锁

- 写入期间存在 `<TargetDir>/.eimmortal.lock`，内含 host/pid/boot_id/started_unix。
- 已存在时 backup 返回 E20；错误信息会把它描述成“另一台主机正在写入”，即使实际是同一台机器上一次被中断的进程。
- `backup --break-lock` 会删除该锁并继续 backup；这是唯一的 CLI 级 TargetDir 锁恢复入口。但它本身也要先拿控制锁：如果控制锁（Windows 标记文件）被卡住，它同样会 E20。
- GUI 的恢复流程：
  1. 用户确认“没有其他 eimmortal/备份进程在跑”；
  2. 若只是要重试 backup，可用 `--break-lock`；
  3. 若用户不想立刻备份，不要用 `backup --break-lock` 做“纯解锁”；应等待上游提供 `lock repair`，或在明确确认后删除锁文件（高风险，需写清影响）。
- 绝不静默删除锁。

### 6.3 取消

- 实测（macOS）：SIGTERM 后进程 exit 130；TargetDir 锁留下；控制锁（Unix flock）随进程退出释放。Windows 强杀可能没有 130，必须按“进程终止 + 锁状态”判断。
- 取消流程：发送终止 → 等待 5 s → 强杀 → 检查锁 → 标记 `interrupted/repair-needed`。
- 下次启动或下次操作前检测“上次中断”：若 `.eimmortal.lock` 存在且 GUI 没有在跑的子进程，展示修复横幅；不要直接开始 backup。
- Windows：Dart `Process.kill` 是 TerminateProcess，控制锁标记文件也会留下；修复流程必须同时考虑 `<vault>/lock`。
- **P0 上游**：优雅取消（context + defer 释放锁），或提供 `eimmortal lock status/repair`。GUI 不应长期依赖手工删文件。

---

## 7. sidecar 路径、完整性与版本

### 7.1 路径

- macOS：`<App>.app/Contents/Resources/bin/eimmortal`（或 `Contents/MacOS/`）；通过 `Platform.resolvedExecutable` 推导，不写死用户路径。
- Windows：`<install>\bin\eimmortal-gui.exe`（GUI 子系统）或 `data\bin\eimmortal.exe`；通过 `Platform.resolvedExecutable` 推导。
- 开发模式：仅在 debug 构建允许 `EIMMORTAL_CORE_PATH` 覆盖；release 构建忽略该变量。
- 不要把 sidecar 作为 Flutter asset 在运行时解压到临时目录：会破坏签名/公证、触发杀软、权限不可控。

### 7.2 完整性

- 构建期计算 sidecar SHA-256，写入 Dart 常量（按平台/架构区分）。
- 启动时校验；在第一次发送密码前再校验一次（或缓存校验结果并监听文件变化）。
- macOS 对 sidecar 单独 `codesign --options runtime`，再签 app；公证包含 sidecar。
- Windows 对 `eimmortal-gui.exe` 做 Authenticode 签名；安装器也签名。
- 生产构建不允许用户指定任意核心路径；否则恶意 sidecar 可以窃取 stdin 中的主密码。
- 版本：启动时跑 `version`，与构建期记录的 `coreVersion`/commit 对比；不一致时禁用操作并要求重装。

### 7.3 Windows 控制台窗口

- 当前 core 的 Windows 产物是 console 子系统；GUI 直接 spawn 可能闪黑框。
- 已实测可用 `-H windowsgui` 构建 GUI 子系统 PE；作为 GUI 专用 sidecar 打包，保留 console 版给终端用户。
- 若 GUI 子系统下 stdin/stdout 管道在 Windows 上不工作，改用原生启动插件：
  `CreateProcessW` + `CREATE_NO_WINDOW` + 重定向管道；仍然调用 console 版 sidecar。
- 这个验证是 M0 spike 的必做项。macOS 还要验证 TCC/Full Disk Access 是否覆盖该子进程；如果不覆盖，sidecar 方案需要重评（FFI/原生）。

---

## 8. 契约测试清单

### 8.1 每个平台（macOS arm64、macOS x64（若支持）、Windows x64）

1. `version`：退出 0，版本匹配。
2. 临时 vault：`init`（stdin 密码）→ 退出 0；`export-key --json` 可解析且有 `armor`。
3. `log --json`：空数组；错误密码 → 10、stdout 空。
4. 备份小目录：`backup --json` → 0、`changed=true`、`seq>=1`；再次备份 → `changed=false`。
5. `status --json`（无密码）→ 0；`status --chain --json`（正确密码）→ 0；检查 `schema=1`、`warnings`。
5b. 错误密码 `status --chain --json`：可能 exit 0 且 `verified=true`；断言 UI 不会把它当“已验证”，而是看 warnings/降级状态。
6. `restore` 到空目录 → 0；`diff -r` 一致；`restore --list-packs --json` 可解析。
7. `verify --sample 1 --json` → 0；删一个 pack → 13 且 JSON 有 `missing`。
8. `doctor --json` → 数组；`doctor --chain`（正确密码）→ 0；篡改/删 journal → 12 且 JSON 有 FAIL。
8b. 错误密码 `doctor --chain` → 12 且某个 check 为 FAIL（不是 E10）；这说明不能只靠退出码区分“密码错”和“数据坏”，所以 UI 必须先 `log` 探针解锁，再跑 doctor。
9. 并发：运行一个长命令，同时跑 `status` → 20。
10. 取消：长备份中途 kill → macOS 期望 130；Windows 只断言进程终止 + 锁状态符合预期（不依赖 130）；修复后重试成功。
11. 错误：无 TTY/无密码源 → 2；错误密码 → 10；不存在 seq → 2。
12. 安全：检查 `ps`/argv 无密码；应用数据目录无密码/临时密码文件；日志无 Armor Key。
13. 解析：所有 JSON 数组的空值 `null` 不导致崩溃；未知字段不导致崩溃。
14. 大输出：大 `log`/`show`/`ls` 不阻塞 UI；必要时用 prefix 限制。
15. 路径：含空格、中文、长路径、Windows 盘符/UNC；配置文件由 TOML writer 生成后 CLI 能正常解析。
16. Windows 控制锁：强杀后 `<vault>/lock` 残留；确认 `backup --break-lock` 在控制锁卡住时也会 E20；验证修复流程或上游 `LockFileEx` 是否生效。

### 8.2 契约测试的产物

- 每个用例保留：命令、退出码、stdout/stderr 摘要、JSON fixture（脱敏）。
- 核心升级时先跑测试，再改 UI；不要反过来。

### 8.3 版本升级检查

- diff `eimmortal <cmd> --help` 的 flag 列表；
- diff JSON 字段（新增可忽略，删除/改名必须适配）；
- 重跑第 8.1 节；
- 特别检查：`restore` 是否新增锚点参数、`status --chain` 是否改为非零、`init` 是否新增 `--json`、Windows 锁实现是否变化。

---

## 9. 已知缺口与 v1 处理

| 缺口 | v1 处理 | 上游建议 |
|---|---|---|
| `init`/`import-key` 无 JSON | 捕获 stdout 到内存；init 后 `export-key --json` 复核；import 后 `status --json` 复核 | P1 加 JSON |
| `backup --dry-run` 无 estimated | 展示文件数/变更数，不显示精确容量；或从人类 stdout 提取（仅显示） | P1 补字段 |
| 进度非结构化 | 日志流 + 不确定进度条；可选正则 | P1 加事件 |
| `restore` 不校验锚点 | restore 前 `doctor --chain`，FAIL 禁止恢复 | P1 内置 |
| `status --chain` 密码错误仍 exit 0 | 用 `log` 做解锁探针；检查 warnings | P1 返回非零/`degraded` |
| `doctor --chain` 密码错误显示 FAIL/E12 | 先解锁，再跑 doctor | P1 区分 E10 |
| `cat` 原始字节 | 不做预览 | P2 流式导出 |
| `ls`/`show`/`log` 无分页 | `ls` 用 prefix；其他限流/虚拟列表；超大时提示 | P1 分页 |
| Windows 控制锁是标记文件 | GUI 修复流程（确认后删除/等待上游） | P0 `LockFileEx` |
| 取消留 TargetDir 锁 | 中断状态 + 修复确认 | P0 优雅取消 |
| 单源根无元数据 | GUI profile 固定 source root | P1 写入 vault.meta |
| 无人值守密码源 | 不做；或明确接受 0600 密码文件（文档已有） | P2 `--password-command`/钥匙串 |
| 无 LICENSE | 发布前选许可证 | 核心/UI 都要 |

---

## 10. 实测证据（2026-10-21，Apple Silicon macOS）

样本：临时 vault + 3 个文件（1 MiB 随机 + 两个文本），真实 `bin/eimmortal`（0.1.0-dev，main 32889e1）。数值仅用于选型，不是性能承诺。

| 项目 | 结果 |
|---|---|
| `init`（`--password-fd 0`） | exit 0，约 2 s；Argon2id t=3 m=1048576 KiB p=4；stdout 含 Armor Key |
| `backup --json` | exit 0；约 0.51 s；peak RSS 1,096,105,984 B；`seq=1` |
| `log --json` | exit 0；约 0.46 s；peak RSS 1,090,912,256 B |
| `status --chain --json` | exit 0；约 0.46 s；peak RSS 1,090,764,800 B |
| `restore --json` | exit 0；约 0.46 s；peak RSS 1,093,222,400 B；`diff -r` 一致 |
| `status --json`（无密码） | exit 0；约 0.014 s |
| 错误密码 `log` | exit 10；stdout 0 B |
| 无 TTY/无密码源 | exit 2 |
| 并发第二个命令 | exit 20 |
| 备份中 SIGTERM | exit 130；`.eimmortal.lock` 留下；下次 backup exit 20；`backup --break-lock` 成功 |
| 切换 source root | seq 2 提交后链加载 E12（RMDIR 非空目录）；证明必须固定源根 |
| 交叉编译 windows/amd64、darwin/amd64、darwin/arm64 | 各 4–5 s；strip 后约 8.9 MB |
| macOS universal sidecar（lipo） | 17 MB；`version` 可运行 |
| Windows `-H windowsgui` 交叉编译 | 成功产出 GUI 子系统 PE；运行期 stdio 待 Windows 验证 |

**未验证**：Windows 上的实际运行、控制锁崩溃残留、GUI 子系统 stdio、macOS 签名/公证后的 sidecar 执行、TCC/Full Disk Access 归属。这些是 M0 spike 的必做项。
