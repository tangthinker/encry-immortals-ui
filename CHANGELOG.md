# Changelog

## 0.4.2 — 2026-10-24

### 变更

- macOS 产物改为 **Developer ID 签名 + Apple 公证 + stapling**：安装后不再需要右键「打开」或执行
  `xattr -dr com.apple.quarantine`，`.app` 与 `.dmg` 都带票据，离线也能通过 Gatekeeper 校验。
- 签名、公证、stapling 全部在 GitHub Actions 完成，证书与公证凭据通过仓库 secrets 注入；
  未配置 secrets 时自动回退 ad-hoc 签名。流程见 [`docs/macos-signing.md`](docs/macos-signing.md)。

### 修复

- 预发布标签（如 `0.4.2-rc1`）下 Windows 安装包编译失败：Inno Setup 的 `VersionInfoVersion`
  只接受纯数字版本号，现由构建脚本剥离 `-rc` 后缀。
- 公证票据分发延迟导致的偶发失败：`stapler` 增加退避重试，`stapler validate` 降级为告警。

## 0.4.1 — 2026-10-24

### 变更

- 新工作区与推荐参数的默认单次备份上限从 1024 MiB（1 GiB）调整为 51200 MiB（50 GB）。
- 已存在的工作区保留原 `config.toml`/profile 中的显式上限，不会在升级时被静默改写。

## 0.4.0 — 2026-10-24

### 功能

- 多工作区：支持新建、导入和切换工作区；每个工作区拥有独立的 `profile.json`、`config.toml` 和本地控制平面。
- 工作区切换器接入侧边栏、解锁页、设置页和启动失败页；切换工作区会锁定当前会话，重新解锁目标工作区。
- 新建/导入过程中使用草稿目录，取消后自动清理并回到原工作区。
- 旧版本单工作区数据会在首次启动时自动迁移到 `workspaces/<id>/`；TargetDir 和备份数据不受影响。
- 主题偏好和单实例锁仍为应用级；工作区只隔离 profile/config/vault。

## 0.3.0 — 2026-10-24

### 功能

- 备份页新增“持续备份到所有数据备份完毕”：当单次备份达到 `session_max_mib` 上限时，可自动重复提交直到不再截断。
- 保留原有“继续备份”按钮，只再执行一次。
- 持续备份显示当前轮次、可停止；检测到 seq/条目没有推进或达到 1000 轮时自动停止，避免无限循环。

## 0.2.2 — 2026-10-23

### 发布

- 保留 macOS universal，同时重新提供独立的 macOS arm64 安装包。

## 0.2.1 — 2026-10-22

### 功能

- 定时备份：每天/每周/每月指定时间，或固定间隔；计划持久化，应用运行且解锁时执行。
- macOS release 改为 x86_64 + arm64 universal 构建，sidecar 也通过 lipo 合并。
- GitHub Actions 新增 Windows x64 构建、Inno Setup 安装包和 portable zip。

## 0.2.0 — 2026-10-22

首个公开 release。

### 功能

- 创建/加入库、解锁、概览、备份、历史、恢复、校验、设置完整流程。
- 创建/加入向导支持普通/高级参数，写入完整 `config.toml`；设置页可修改全部已实现参数。
- 原生 macOS 菜单栏、快捷键、内容化窗口标题；macOS/Windows 应用图标。
- 默认浅色外观，可在设置页切换浅色/跟随系统/深色，偏好持久化。
- 侧边栏直接锁定按钮与设置 tab。

### 打包

- macOS release 带签名后固定 SHA-256 的 sidecar；构建期校验 bundle 内哈希。
- 新图标包含 macOS 全套 AppIcon 与 Windows 多尺寸 ICO。
- GitHub Actions 在 `v*` tag 上构建 macOS `.zip` / `.dmg` 并创建 release。

### 已知限制

- macOS 使用 ad-hoc 签名，未公证，未做 universal 单包。
- Windows 构建脚本已提供但尚未在 Windows 宿主/CI 实测。
