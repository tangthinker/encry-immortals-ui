# Changelog

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
