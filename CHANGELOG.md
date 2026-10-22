# Changelog

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
