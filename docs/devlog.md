# 开发日志

> 项目：encry-immortals-ui（eimmortal 桌面客户端）
> 约定：每个里程碑按时间倒序记录「目标 / 操作 / 结果 / 决策 / 风险 / 下一步」。命令与输出只保留可复现的关键部分，不记录密码、Armor Key、明文文件列表。

---

## 2026-10-22 23:00 · 定时备份：每天/每周/每月/固定间隔

### 目标

支持每天、每周、每月指定时间执行一次备份，也支持每 N 分钟/小时/天执行一次。

### 设计约束

- 主密码不落盘，因此**没有锁定时自动解锁**；调度器只在应用运行且 vault 已解锁时执行。
- 应用完全退出时没有后台进程；下次启动解锁后，如果计划时间已过，补跑一次。
- 不引入系统级 launchd/Task Scheduler，也不保存密码到 Keychain。

### 计划模型

新增 `lib/core/backup_schedule.dart`：

- `off / daily / weekly / monthly / interval` 五种模式。
- 每天/每周/每月支持本地时间 `HH:mm`；每周支持周一..周日；每月 1..31，短月份自动使用最后一天。
- 固定间隔 5 分钟..30 天，按分钟存储，UI 支持分钟/小时/天。
- `nextAfter(now)` 纯函数计算下次执行；`nextRunAt`、`lastRunAt`、`lastError` 持久化。
- 计划存入 `profile.json` 的 `schedule` 字段，旧 profile 自动视为关闭。

### 调度器

`AppController` 内新增 30 秒检查一次的 `Timer`：

- initialize 时恢复 `nextRunAt`；缺失但已启用的计划自动计算并保存。
- 解锁成功后立即检查一次；锁定、命令运行中时跳过本轮并保留 due 状态。
- 到点、已解锁、队列空闲时调用 `session.backup(message: '定时备份')`。
- 成功后刷新 status/target lock、更新上次/下次时间并递增数据版本；失败写入 `lastError` 和下一次时间，避免每 30 秒重试轰炸。
- 定时备份完成后通过 `scheduledBackupRevision` 让 shell 显示 SnackBar。
- 删除本地 profile、dispose 时取消 Timer。
- 计划修改会立即计算新的 `nextRunAt` 并重启 Timer。

### 设置界面

设置页新增“定时备份”卡片：

- 频率下拉：关闭/每天/每周/每月/固定间隔。
- 时间选择器（本地时区、24 小时制）；每周选择星期；每月选择日期；固定间隔输入数值+单位。
- 显示当前计划、下次执行、上次执行、上次错误。
- 明确提示：应用必须保持运行并已解锁；锁定/错过时解锁后补跑；应用完全退出时不会后台执行。

截图：[定时备份设置](assets/m1-settings-schedule-light.jpg)。

### 验证

```text
flutter analyze                 No issues found
flutter test                    86 passed, 3 skipped
新增测试                       backup_schedule_test（每天/每周/每月/间隔/边界/JSON）
                               profile_test（schedule 往返）
```

构建：

```text
flutter build macos --debug     成功
flutter build macos --release   成功；bundle integrity: verified
```

### 风险 / 取舍

- 不是系统级调度：应用被彻底退出时不会触发；这是“主密码不落盘”的直接结果。
- 定时任务与应用命令共享串行队列；到点若正在执行其他命令，会延后到队列空闲再执行。
- 如果用户恰好在同一时间手动备份，可能出现一次额外提交；后续可在队列层做“刚完成手动备份”去重。
- 月计划 31 日在短月按最后一天执行；UI 已提示。

---

## 2026-10-22 22:40 · 侧边栏锁定/设置 tab + 默认浅色主题

### 目标

1. 侧边栏顶部三个点改成直接的锁定按钮。
2. 设置从顶部菜单移回侧边栏，作为第六个 tab。
3. 应用默认浅色主题；设置页可切换“浅色 / 跟随系统 / 深色”。

### 操作

- 侧边栏顶部 `PopupMenuButton` 替换为 `IconButton`（`lock_outline`）：
  - 命令运行时禁用，tooltip 说明“命令运行中，暂不能锁定”；
  - 不再承载设置入口，减少“更多”菜单的隐藏操作。
- 设置作为 `_NavItem` 加回侧边栏（概览/备份/历史/恢复/校验/设置），选中有高亮；
  - 应用菜单 `⌘,`、`Ctrl+,` 仍保留，作为桌面惯例入口；
  - 窗口标题仍随 tab 变化。
- 新增 `AppThemeMode { light, system, dark }` 和 `AppPreferencesStore`：
  - 偏好落在应用数据目录 `preferences.json`（0600），独立于 vault profile；
  - 缺少/损坏文件回退浅色；移除本地 vault 配置不会重置主题；
  - `AppController` 默认 `light`，initialize 时加载偏好；`setThemeMode` 先更新内存再持久化，失败回滚。
- `EncryImmortalsApp` 监听 controller 与系统亮度：
  - 浅色/深色固定；
  - 跟随系统时监听 `didChangePlatformBrightness`；
  - 切换后立即重建主题，State 保留。
- 设置页新增“外观”卡片：
  - 三段式 SegmentedButton：浅色 / 跟随系统 / 深色；
  - 当前状态提示（浅色默认）；
  - 保存失败显示错误横幅；命令运行中暂时禁用切换。
- 默认浅色意味着首次启动、onboarding、解锁页都直接是浅色，除非用户保存过偏好。

### 验证

```text
flutter analyze                 No issues found
flutter test                    77 passed, 3 skipped
flutter build macos --debug     成功
flutter build macos --release   成功；bundle integrity: verified
```

新增测试：

- `test/core/app_preferences_test.dart`：默认浅色、持久化/0600、损坏回退。
- `test/app/app_controller_test.dart`：默认浅色、跨 controller 持久化。
- `test/app/theme_mode_test.dart`：默认浅色、切深色、跟随系统随平台亮度变化。

截图：新侧边栏锁定按钮/设置 tab、外观卡片，见 [dashboard](assets/m1-dashboard.jpg)、
[dashboard 浅色](assets/m1-dashboard-light.jpg)、[settings 浅色](assets/m1-settings-light.jpg)。

### 已知取舍

- macOS 原生标题栏由系统外观决定，不会跟随应用内“固定深色/浅色”；这是系统窗口框架的限制。
- 设置 tab 与应用菜单设置入口同时存在，分别服务发现性和快捷键习惯。
- 主题偏好是应用级，不随 vault profile 切换；单 profile 场景下没有歧义。

---

## 2026-10-22 22:35 · 界面内统一使用新图标

### 目标

应用图标换成“封印 + 无穷”后，界面里还残留旧盾牌标记（侧边栏、onboarding、解锁、启动页）。
这一轮把界面内的品牌标记与应用图标统一。

### 操作

- 新增 `assets/icon/app-mark.png`：从 `macos-small` 裁掉 macOS 1024 图标的 100px 透明外边距，
  缩到 256px。这样在 UI 里显示 36/40px 时视觉尺寸与旧方形 logo 一致，不会突然变小。
- `AppMark` 从“黄铜圆角底 + `shield_moon` 图标”改为 `Image.asset` 新图标；作为装饰图像加入
  语义树（紧邻应用名，避免 VoiceOver 重复读应用名）。
- 侧边栏顶部移除自定义盾牌 Container，统一用 `AppMark(size: 36)`；onboarding/解锁/启动/
  已运行页面继续用同一个 `AppMark`。
- `assets/icon/app-mark.png` 声明到 `pubspec.yaml`，由 `tool/generate_icons.py` 自动生成。
- 重新截图：dashboard、onboarding、onboarding 参数页、解锁、设置、备份、历史、恢复、校验
  全部换成新标记。

### 未替换的盾牌

onboarding 的“安全提示”里仍保留一个 `Icons.shield_outlined`：它是语义图标，不是品牌标记，
用来提示安全说明，不应换成应用图标。

### 验证

```text
flutter analyze                 No issues found
flutter test                    72 passed, 3 skipped
flutter build macos --debug     成功
flutter build macos --release   成功；bundle integrity: verified
```

新截图：[dashboard](assets/m1-dashboard.jpg)、[dashboard 浅色](assets/m1-dashboard-light.jpg)、
[onboarding 参数](assets/m1-onboarding-params.jpg)、[解锁](assets/m1-unlock.jpg)。

### 风险

- Windows 任务栏/开始菜单仍建议实机确认；Flutter UI 内的 AppMark 在 Windows 上使用同一 assets PNG。
- 若 macOS 仍显示旧 Dock 图标，是图标缓存；UI 内的 AppMark 不受影响。

---

## 2026-10-22 22:30 · 应用图标重做：封印 + 无穷（不再使用字母/钥匙）

### 目标

原图标（钥匙孔）和本轮的骨架钥匙稿都被判定不好看。重做一个独立的品牌图标：
不要字母、不要具象钥匙、不要渐变/AI 味的霓虹或玻璃质感；macOS 与 Windows 都要有各自合适的版本。

### 最终方案

**黄铜蜡封压在纸面上的“无穷”标记**：

- 无穷符号 = Immortals 的“永续” + 备份链的“链环”；比字母 E 更抽象，比钥匙更克制。
- 外圈是手压蜡封的 26 瓣不完美边缘；内圈是纸面嵌片，带轻微纸纤维与压印阴影。
- 无穷用深墨色“压”在纸上，保留 letterpress 的偏移阴影；没有渐变、没有高光塑料感。
- 极简三色：深墨 `#10161A`、黄铜 `#C9A35B`、纸 `#EADFCB`；辅助暗黄铜/纸影。
- macOS 使用 824/1024 的 squircle 网格（superellipse，不是普通圆角矩形）；Windows 版本去 tile、透明背景，加平滑深色轮廓。

### 被否决的方向

| 方向 | 否决原因 |
|---|---|
| 骨架钥匙 | 太具象、粗黑钥匙齿在 16px 像图标字体，确实不好看 |
| 字母 E 圆章 | 太像通用 monogram，缺少产品故事 |
| 文档 + 火漆章 | 340px 好看，16px 像收据/备忘录 |
| 两节链环 / 结 | 缩小后变成一坨，交叉关系不清晰 |
| 中心铆钉 / 绿色弧线 | 铆钉像眼睛，绿色弧线像划痕；删掉更干净 |
| 顶部挂环 | 像怀表/奖章，偏离备份语义 |

### 平台优化

- **macOS**：`macos-master`（128–1024，完整细节）、`macos-small`（32/64，简化蜡封与加粗无穷）、`macos-tiny`（16，去掉纸纹/环刻，保证小尺寸对比）。
- **Windows**：透明背景；`windows-small`（16–48，厚金环 + 深轮廓）、`windows-master`（64–256，完整细节 + 平滑深色轮廓）。ICO 使用 16/24/32/48/64/128/256 七个 PNG 条目（Vista+）。
- macOS 资源目录：16/32/64/128/256/512/1024；Windows ICO 已用 `file` 与 PIL 验证 7 个尺寸。

### 文件

```text
assets/icon/
  macos-master.svg/png      完整设计源 + 1024 master
  macos-small.svg/png
  macos-tiny.svg/png
  windows-master.svg/png
  windows-small.svg/png
  README.md                 设计说明 / 重新渲染方法
tool/generate_icons.py      从 PNG masters 生成平台资源
tool/render_icon_svgs.py    用 headless Chrome 从 SVG 重渲染 masters
```

设计完全矢量（无字体依赖）；PNG masters 已入库，因此 release 构建不依赖 Chrome。

### 验证

```text
tool/generate_icons.py       macOS 7 sizes + Windows ICO 7 sizes
PIL ICO check                16/24/32/48/64/128/256
flutter build macos --debug  成功；Assets.car 含 AppIcon renditions
assetutil --info              AppIcon 16..1024 均存在
flutter build macos --release 52 MB；bundle 签名与 sidecar 校验通过
app icon preview              docs/assets/app-icon-preview.jpg
```

预览：[app-icon-preview.jpg](assets/app-icon-preview.jpg)；原图 [app-icon.png](assets/app-icon.png)。

### 风险 / 下一步

- 尚未在 Windows 实机检查任务栏/开始菜单的实际观感；ICO 使用 PNG 条目，Windows 10+ 支持。
- macOS 可能缓存旧图标；升级安装后如仍显示旧图，需要清理图标缓存或重启 Dock。
- 图标是品牌资产，后续若改主色/蜡封方向，需要同步更新 5 个 SVG 与 masters并重跑生成器。

---

## 2026-10-22 21:20 · 参数设置：初始化向导 + 设置页全参数

### 目标

1. 创建/加入库的初始化流程增加“参数设置”步骤，明确分为普通参数和高级参数。
2. 应用内的设置页可查看/修改全部**当前版本实际生效**的 sidecar 参数，并真正写入 `config.toml`。

### 一、配置模型

新增 `lib/core/vault_settings.dart`：

- 普通参数：`session_max_mib`、`zstd_level`、`scan.mode`、`scan.exclude`。
- 高级参数：`pack_max_bytes`、`slice_plain_bytes`、`small_file_bytes`、`min_compress_bytes`、
  `staging_dir`、`ignore_xattr`、`sparse_max_bytes`、`follow_hardlinks`、`on_change_during_read.strategy`。
- 大尺寸在 UI 用 MiB/KiB，写 TOML 时换算为字节；校验包含 `slice+50B ≤ pack`、`small+50B ≤ pack`、
  slice ≤ 64 MiB、zstd 1..22、路径必须是绝对路径/`~/` 等跨字段规则。
- 不暴露上游未实现字段（`concurrency.hashers`、`checkpoint.*`、`verify.auto_strict_every`），避免设置看似生效。

`VaultConfig` 现在写出完整配置段：

```toml
[storage]
target_dir = "…"
staging_dir = "…"          # 可空
pack_max_bytes = 134217728
slice_plain_bytes = 33554432
small_file_bytes = 67108864
session_max_mib = 1024

[codec]
zstd_level = 5
min_compress_bytes = 4096

[scan]
mode = "fast"
exclude = [".git/**", "node_modules/**", "*.tmp", ".DS_Store"]
follow_hardlinks = "error"
ignore_xattr = true
sparse_max_bytes = 0

[on_change_during_read]
strategy = "retry"
```

`profile.json` 增加嵌套 `settings`，同时继续写旧的 `session_max_mib`/`ignore_xattr` 字段；旧 profile
没有 `settings` 时自动按扁平字段迁移。`TargetDir`、应用控制平面目录、源根目录仍固定，不提供修改入口。

### 二、初始化向导

- 创建/加入流程由 3 步扩展为 4 步：选择目录 → 主密码 / Key → **参数设置** → 确认。
- 参数设置页复用 `VaultSettingsForm`：普通参数直接展开；高级参数用可折叠区，默认收起。
- 高级区包含 pack/slice/small、最小压缩阈值、暂存目录选择器、xattr、稀疏文件、硬链接和读取中变化策略。
- 确认页显示参数摘要（会话上限、zstd、扫描模式、排除条数、pack/slice/small）。
- 参数在 `init`/`init --join` 之前写入 `config.toml`，因此首次命令就使用用户选择的参数。

### 三、设置页

- 设置页新增“备份参数”卡片，放在“当前库”之后，使用同一个表单；保存按钮写入 config+profile。
- 保存前做跨字段校验；命令运行中禁用编辑/保存；失败显示错误横幅。
- 结构性参数（pack/slice/small_file）变更时二次确认“只影响后续提交，已有快照仍可读”。
- 在 macOS 上关闭 `ignore_xattr` 时二次确认 E21 风险。
- 保存后立即更新内存中的 profile/session，下一次 sidecar 命令生效；不需要重启应用。

### 四、验证

```text
flutter analyze                         No issues found
flutter test                            72 passed, 3 skipped（integration 默认跳过）
真实 sidecar integration                3 passed
  - 自定义参数创建（pack 64 MiB / slice 8 MiB / zstd 9 / strict / split / skip）
  - 更新全部参数后 config.toml 断言
  - refreshPreviewStatus 确认 sidecar 接受新配置

flutter build macos --debug             成功；Debug/Profile sidecar 注入
flutter build macos --release           53.7 MB
tool/verify_bundle.dart                 source=bundle, integrity: verified（core v0.1.5）
```

新增测试：

- `test/core/vault_settings_test.dart`：默认值、边界、跨字段约束、JSON 往返、legacy 扁平迁移。
- `test/core/vault_config_test.dart`：全部 TOML 字段、空 exclude、非法参数、0600。
- `test/app/vault_settings_form_test.dart`：普通/高级分组、字段读取、校验横幅、恢复推荐值。
- `test/app/onboarding_screen_test.dart`：通过 fake directory selector 走完目录→密码→参数→确认四步。
- `test/core/profile_test.dart`：完整 settings 往返与旧 profile 迁移。

截图：[初始化参数（深色）](assets/m1-onboarding-params.jpg)、[初始化参数（浅色）](assets/m1-onboarding-params-light.jpg)、
[设置参数（深色）](assets/m1-settings-params.jpg)、[设置参数（浅色）](assets/m1-settings-params-light.jpg)。

### 五、取舍 / 风险

- 不提供 `TargetDir`、vault 目录修改；换 TargetDir/换源需要新建 profile。
- 暂存目录只做绝对路径校验，是否与 TargetDir 同卷由 sidecar 在命令启动时最终判定。
- 结构性参数变更对已有快照的影响依赖上游“每次提交记录参数快照”的保证；界面已明确提示并二次确认。
- 设置页仍是主窗口内页面，不是独立 Settings 窗口；侧边栏隐藏、Idle 自动锁定仍未做。
- Windows 仍只做了代码路径与构建脚本，未在 Windows 宿主实测。

### 六、下一步

1. Windows 实机验证参数写入、暂存目录同卷与锁行为。
2. 补齐配置文件导入/导出与“恢复默认参数”的显式审计记录。
3. 将设置页拆为独立 macOS Settings 窗口，并补 Increase Contrast 变体。

---

## 2026-10-22 01:25 · 修复 `flutter run` sidecar 注入 + Apple HIG 设计打磨

### 目标

1. `flutter run -d macos` 不再因为找不到 sidecar 停在“无法启动”页。
2. 按 [apple-design skill](https://github.com/dickwu/apple-design-skill) 做一次完整的 UI/交互审计与改进，并同步完善功能。

### 一、sidecar 注入修复

**问题**：Debug 构建的 `Contents/Resources/bin/` 为空，`CoreLocator` 只能找到 `Contents/MacOS/eimmortal`，于是报“找不到核心 sidecar”。

**修复**：

- 把核心仓库固定为 git submodule：`third_party/encry-immortals` @ `v0.1.5`；移除 `.gitignore` 里的排除项。
- 新增 `tool/xcode_debug_sidecar.sh`，并在 Runner 的 build phases 末尾加入 `Debug/Profile Sidecar` phase：
  - Debug 时优先使用 `EIMMORTAL_CORE_PATH`；
  - 否则从 submodule 用 `CGO_ENABLED=0` 构建 host 架构 sidecar；
  - 复制到 `Contents/Resources/bin/eimmortal`，ad-hoc 签名；
  - Release 由 `tool/build_macos.sh` 统一签名 + 哈希固定。
- `setAppWindowTitle` 前增加 `initAppWindow()` 守卫：window_manager 未初始化时绝不触碰窗口 API，避免 Swift 侧 `mainWindow!` 崩溃。
- Release 构建改用 submodule 的 `v0.1.5`，hash 变为 `3f42019c…9302faff`，bundle 校验 `integrity: verified`。

**证据**：截图 [settings](assets/m1-settings-light.jpg) 的 sidecar 路径已经是
`…/Debug/Encry Immortals.app/Contents/Resources/bin/eimmortal`，说明 Debug phase 生效；plain `flutter run` 启动无错误。

### 二、Apple HIG 审计（阅读的参考）

按 skill 的 always-load + desktop 集合阅读：
`accessibility.md`、`layout.md`、`typography.md`、`color.md`、`designing-for-macos.md`、
`sidebars.md`、`toolbars.md`、`windows.md`、`settings.md`、`the-menu-bar.md`、`keyboards.md`、
`buttons.md`、`progress-indicators.md`。

**主要发现**

| 严重度 | 问题 | 依据 |
|---|---|---|
| Critical | `faint` 文字 #63718B 在卡片上只有 3.40–3.95:1，小字号不达 4.5:1 | `accessibility.md › Vision`；`typography.md › Ensuring legibility` |
| High | 只有深色外观，没有跟随系统浅色/深色 | `color.md › Best practices`；`designing-for-macos.md` |
| High | 没有原生菜单栏，所有命令只能点页面按钮；快捷键缺失 | `the-menu-bar.md › Anatomy`；`toolbars.md › Desktop`；`keyboards.md` |
| High | 关键操作“锁定”放在侧边栏底部；窗口标题是应用名 | `sidebars.md › Desktop`；`windows.md › Best practices`；`toolbars.md › Titles` |
| High | 默认 Flutter 应用图标；整体接近“近黑 + 酸性绿”生成模板 | skill Craft lens；`app-icons.md` |
| Medium | 9.5pt 小字低于 macOS 10pt 最小值；大量重复的“锚点”信息 | `typography.md › Ensuring legibility`；`layout.md › Visual hierarchy` |

### 三、已实施的改进

1. **系统浅色/深色**：`AppColors` 改为语义色板，跟随 `platformBrightness`，无应用内主题开关；浅色不是简单反色，而是羊皮纸底 + 深黄铜。
2. **可访问性**：
   - 对比度全部 ≥ 4.5:1，新增 `test/app/theme_contrast_test.dart` 强制两种外观都过；
   - 最小字号提升到 10pt；控件保持 macOS 紧凑命中区；
   - 状态同时使用图标+文字，不用颜色单独表达；
   - 过渡动画尊重 `MediaQuery.disableAnimations`。
3. **桌面惯例**：
   - 原生菜单栏：应用/文件/编辑/显示/操作/窗口/帮助；含 About、Settings…、Quit、编辑标准项、全屏/最小化；
   - 快捷键：⌘1–5 切换页面、⌘⇧B 备份、⌘⇧R 恢复、⌘Y 校验、⌘R 刷新、⌘L 锁定、⌘, 设置；
   - 窗口标题改为当前内容（概览/备份/…），不再用应用名；
   - 锁定与设置移到侧边栏顶部“更多”菜单 + 应用菜单，底部只保留版本等非关键信息；
   - 设置页增加“完成”，⌘, 可进入。
4. **视觉识别**：
   - 黄铜主操作、绿色“已验证”、琥珀警告、红色危险；
   - 新增 `ChainSeal`：由 `anchor_short` 与 verified 数据驱动的“封印”，替代重复的锚点行；
   - 应用图标改为“封印 + 钥匙孔”，`tool/generate_icons.py` 生成 macOS 全尺寸 + Windows ICO；
   - 字体仍是系统 SF + Menlo 数据字体，层级由字号/字重/颜色承担。
5. **功能完善**：
   - 刷新现在是真实命令（菜单/⌘R 会触发 Dashboard/History/Restore 重新拉取）；
   - 写锁状态、备份/恢复预检、成功色语义与浅色主题统一；
   - debug sidecar 自动注入，首次运行不再需要手工导出环境变量。

### 四、验证

```text
flutter analyze                         No issues found
flutter test                            62 passed, 3 skipped（集成默认跳过）
theme contrast (dark + light)           全部 ≥ 4.5:1
真实 sidecar integration                3 passed（含 13 步垂直切片、完整链路、AppController）
flutter build macos --debug             成功；Debug phase 注入 sidecar
flutter build macos --release           53.7 MB，core v0.1.5
tool/verify_bundle.dart                 source=bundle, integrity=verified
```

新增截图：[onboarding](assets/m1-onboarding-light.jpg)（浅色）、[dashboard](assets/m1-dashboard.jpg)（深色）、
[dashboard 浅色](assets/m1-dashboard-light.jpg)、[unlock](assets/m1-unlock-light.jpg)、[settings 浅色](assets/m1-settings-light.jpg)。

### 五、剩余问题 / 取舍

- [ ] 设置仍是主窗口内的页面，不是独立的 fixed-toolbar Settings 窗口；侧边栏也不支持手动隐藏。
- [ ] 菜单里的“备份/校验/恢复”是导航命令，参数仍需在页面确认；没有把“开始备份”做成菜单直接执行。
- [ ] Edit 菜单的 Cut/Copy/Paste 通过 `Actions.maybeInvoke` 转发，尚未逐项手工验证焦点不在文本框时的行为。
- [ ] Windows 宿主构建、GUI 子系统 stdio、Windows 控制锁未实测；仅 ad-hoc 签名，未公证。
- [ ] 空闲自动锁定、上次中断状态持久化、大快照分页仍未做。

### 六、下一步

1. Windows CI/实机验证 + Authenticode + 安装器。
2. 设置窗口化、侧边栏显示/隐藏、菜单动作直接执行。
3. Developer ID + notarytool + stapling。
4. 空闲自动锁定与启动时“上次中断”恢复提示。

---

## 2026-10-21 23:18 · M1 MVP 完成：从演示壳层到真实产品流程

### 目标与范围

把 M0 的“只有自检页的壳层”替换成可实际使用的单 profile 客户端：创建/加入库、解锁、仪表盘、备份、历史、恢复、校验、设置，
并按发布要求把 sidecar 打进 app bundle、签名、固定 SHA-256。范围按 `tech-selection.md` 的 M1，不含定时备份、自动更新、多 vault。

### 产品/架构决策

1. **删除所有渐变**：颜色改为纯色 surface/border/accent；`grep -rn "Gradient" lib` 为空。
2. **删除 app 内调试功能**：移除 M0 自检页、截图钩子、`EIMMORTAL_AUTORUN_SELFTEST`、`dev_capture.dart`。
   垂直切片保留在 `tool/vertical_slice.dart` 与 core 中，只作为开发/测试工具，不再出现在 UI。
3. **移除 Riverpod，改为单一 `AppController` + ChangeNotifier**：单窗口、单 profile 的状态不需要额外容器；
   onboarding/unlock/shell 用 phase 状态机，页面局部状态自管。依赖缩减为 `file_selector`、`window_manager`、`crypto`、`path`。
4. **应用私有控制平面**：`~/Library/Application Support/EncryImmortals/vault`，不读写 CLI 的 `~/.eimmortal`；
   TargetDir 仍由用户选择，移除配置不删除 TargetDir。v1 单 profile，避免与 CLI/多实例共享锚点状态。
5. **源根目录固定**：创建时记录到 profile，设置页只读；换源必须移除配置后重新加入，防止同一 TargetDir 的链语义破坏。
6. **所有真实命令经 `CommandQueue` 单飞**；任务通过 `QueueTicket.attach(run.cancel)` 注册取消，取消后等子进程退出再允许退出应用。

### 新增/重写

| 路径 | 内容 |
|---|---|
| `lib/app/app_controller.dart` | 启动、单实例、核心定位/哈希校验/版本、profile 装载、preview status、解锁/锁定、配置更新、退出 |
| `lib/core/app_paths.dart` | macOS/Windows 应用数据目录，0700 |
| `lib/core/profile.dart` / `profile_store.dart` | profile schema、原子写入、0600、TargetDir 保护 |
| `lib/core/instance_lock.dart` | 单实例文件锁 |
| `lib/core/progress.dart` | 备份/还原 stderr 进度解析，仅用于显示 |
| `lib/core/lock_inspector.dart` | TargetDir 写锁读取/删除、Windows 控制锁标记 |
| `lib/core/vault_session.dart` | 解锁、status/history/show/ls、backup/restore/verify/doctor、export-key、控制锁探测 |
| `lib/core/onboarding_service.dart` | 创建/加入库的完整命令序列、校验、失败清理（绝不删 TargetDir） |
| `lib/app/screens/**` | onboarding、解锁、主壳层、概览、备份、历史、恢复、校验、设置 |
| `lib/app/widgets/snapshot_tree.dart` | 快照文件树、展开/折叠、路径过滤 |
| `tool/build_core.sh` / `build_macos.sh` | sidecar 构建/签名/哈希、release app 打包 |
| `tool/verify_bundle.dart` | bundle 路径、SHA-256、版本验证 |

### 关键流程实现

- **创建**：校验源/TargetDir 不重叠、TargetDir 为空 → config.toml(0600) → `init`(stdin) → `export-key --json` → 保存 profile。
  失败会清理本次写下的 config/vault；`init` 成功后才删本地 vault，TargetDir 永不被删。
- **加入**：config → `init --join` → `import-key`(stdin) → `log` 验证密码 → `doctor --chain` → 保存 profile。
- **解锁**：`log --json` 探针；成功才把密码留在 session；每次解锁前重新校验 sidecar 哈希。
- **备份**：`--dry-run` / 正式；stderr 日志 + 百分比进度；`truncated` 提供“继续备份”；E20/取消时展示锁文件 host/pid/started，
  支持 `--break-lock` 重试；启动/备份后检测 TargetDir 写锁，在解锁页与主壳层显示横幅，设置页提供诊断与删除（高风险二次确认）。
- **历史**：`log` → `show` → `ls --at`；文件树支持过滤与折叠；读取全部在内存。
- **恢复**：强制 `doctor --chain` → `restore --list-packs`；缺失时要求“等待同步”或“跳过缺失 pack”二选一；
  覆盖策略 `never/if-changed/always`，`always` 二次确认；支持 dry-run；E13/E12 仍解析 JSON 展示部分结果。
- **校验**：`verify --sample N/--deep` + `doctor --chain`，PASS/WARN/FAIL 表格与失败项列表。
- **设置**：profile/路径/核心完整性、`session_max_mib` 修改、导出 Armor Key（重新验证密码）、写锁诊断、立即锁定、移除本地配置、退出。
- **退出保护**：window_manager 拦截关闭；命令运行中弹窗确认取消并等待队列 idle；单实例文件锁避免两个 UI。

### 打包与签名

`tool/build_macos.sh` 的实际顺序：

1. `go build`（`CGO_ENABLED=0`，记录 `git describe`）→ `build/core/eimmortal`；
2. **先 `codesign` sidecar，再计算 SHA-256**；
3. `flutter build macos --release --dart-define=EIMMORTAL_CORE_SHA256=...`；
4. 复制已签名 sidecar 到 `Contents/Resources/bin/`，签 app，校验 bundle 内哈希。

实测：

```text
core: v0.1.5-4-g340cade
sha256: d9fd1170eef95cc01c4a4431a2b2f2e7fbb36176603502f88cfce1563051dbf5
app: build/macos/Build/Products/Release/Encry Immortals.app (53.3 MB)
codesign --verify --deep --strict: valid
dart run tool/verify_bundle.dart ...: source=bundle, integrity=verified
```

### 遇到的问题与修复

1. **codesign 改写 Mach-O**：先算哈希再签名会导致运行时 `mismatch`。改为先签 sidecar、后算哈希，并把“bundle 内哈希 == 构建期常量”
   作为脚本的最后一道断言。
2. **sidecar 路径相对值**：`Process.start` 的工作目录是用户主目录，相对路径直接 `No such file or directory`；`CoreLocator` 统一返回绝对路径。
3. **shell 变量紧邻中文**：`$CORE_HASH）` 被 bash 当成变量名的一部分，`set -u` 报 unbound variable；脚本统一改成 `${VAR}`。
4. **widget test 中的真实 I/O**：`testWidgets` 的 fake async 不会驱动 `chmod`/文件写入，`await` 会挂起；组件测试必须把真实 I/O 放进
   `tester.runAsync`，或改用普通 `test`。据此删除了之前临时的主页面 smoke 测试，保留真实链路的普通 integration test。
5. **macOS 构建警告**：Xcode 提示 CoreSimulator 版本旧、Run Script 无 outputs；只影响 iOS 模拟器/构建提示，不影响 macOS 产物。
6. **截图验证**：当前会话无屏幕录制权限，临时使用 `lib/dev_capture.dart` 的 RepaintBoundary 截图（已删除）；截得
   onboarding / unlock / dashboard / backup / history / restore / verify / settings，保存在 `docs/assets/m1-*.jpg`。
7. **App Sandbox**：沿袭 M0 结论，entitlements 已无 `com.apple.security.app-sandbox`；`codesign -d --entitlements` 复核。

### 验证结果

```text
flutter analyze                          No issues found
flutter test (不含真实 sidecar)           59 passed
integration（3 个用例）                    passed（垂直切片 + 完整链路 + AppController 生命周期）
flutter build macos --release             53.3 MB，ad-hoc 签名通过
tool/verify_bundle.dart                   source=bundle, integrity=verified
```

真实链路覆盖：创建库 → 备份 → log/show/ls → status --chain → doctor → restore list-packs → restore → verify → export-key →
第二台“机器”加入同一 TargetDir → 再次备份。AppController 覆盖：initialize → create → activate → lock → unlock →
`session_max_mib` 写回 config/profile。integration 全量约 12 s。

### 风险与未完成

- [ ] Windows 宿主构建、`eimmortal-gui.exe` stdio、Windows 控制锁崩溃残留均未实测；脚本已写但未验证。
- [ ] 仅 ad-hoc 签名，未做 Developer ID / notarization / Authenticode；不能直接对外分发。
- [ ] 空闲自动锁定、上次中断状态持久化、崩溃后自动提示未做。
- [ ] `ls` 仍一次加载整个快照树；大快照需要分页/前缀懒加载。
- [ ] 应用私有控制平面与 CLI `~/.eimmortal` 不共享；不能同时用 CLI/GUI 操作同一 TargetDir。
- [ ] 上游 P0（Windows `LockFileEx`、优雅取消）仍未落地，当前取消依赖 SIGTERM + 锁诊断。

### 下一步

1. 在 Windows 机器/CI 上跑 `tool/build_windows.ps1`，验证 GUI sidecar stdio 与锁；补 Windows 安装器。
2. Developer ID + notarytool + stapling；Windows Authenticode。
3. 空闲自动锁定、上次中断状态持久化、锁修复后的自动重试。
4. 大快照分页/前缀懒加载；上游结构化进度（`--events=ndjson`）。
5. 与上游确认是否共用控制平面；若共用，设计 profile 导入/迁移流程。

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
