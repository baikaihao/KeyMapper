# Changelog

All notable changes to KeyMapper will be documented in this file.

## [2.0.1] - 2026-04-22

### Added
- **全新原生 macOS 界面**：采用 NavigationSplitView 侧边栏导航布局
- **检查更新功能**：通过 GitHub Releases API 检查新版本
- **导入导出功能**：支持备份和恢复映射规则为 JSON 文件
- **关于页面**：显示版本信息、许可证和技术支持链接
- **GitHub 图标**：关于页面使用 GitHub 官方图标

### Changed
- **界面重构**：完全重新设计 UI，采用原生 macOS 窗口风格
- **规则列表**：四列布局（原键、映射为、启用、操作），隔行变色提高可读性
- **录制按键**：点击范围扩大至整个按键块区域
- **垃圾桶图标**：全局改为红色，更易识别
- **版本号**：从 Info.plist 动态读取

### Fixed
- **窗口显示**：修复菜单栏"显示窗口"显示旧样式小窗口的问题
- **规则列表滚动**：修复底部规则被录制区域遮挡的问题
- **导出导入**：完善错误处理和成功提示

## [1.5.0] - Previous Release

### Features
- Global key remapping using CGEventTap
- Visual key recording
- Modifier key support (Command, Option, Shift, Control)
- Radial wheel for multiple mappings
- Pause hotkey
- App blacklist
- Stealth mode (hide Dock icon)
- Launch at login

---

## Version History

| Version | Date | Description |
|---------|------|-------------|
| 2.0.1 | 2026-04-22 | 全新界面重构，新增检查更新、导入导出功能 |
| 1.5.0 | 2026-04-22 | 基础功能版本 |
