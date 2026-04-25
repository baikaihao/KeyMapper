# Changelog

All notable changes to KeyMapper will be documented in this file.

## [2.1.0] - 2026-04-25

### Added
- **规则备注功能**：为每条映射规则添加备注说明，方便记忆和管理
- **自动备份功能**：
  - 支持定时自动备份映射规则
  - 可设置备份间隔（1-14天）
  - 可设置最大备份数量（1-20个），超过自动删除最旧的备份
  - 默认备份路径为 `~/Documents/KeyMapperRules`
  - 支持自定义备份路径
  - 一键打开备份文件夹
- **深色模式图标**：APP图标和关于页面图标支持深色模式自动切换
- **未授权提示优化**：侧边栏未授权状态新增"请授权后重启"提示

### Changed
- **导入导出优化**：文件选择器默认打开备份路径
- **数据兼容性**：优化数据模型，支持向后兼容旧版本配置

### Fixed
- **数据迁移**：修复添加备注字段后旧数据兼容性问题

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
| 2.1.0 | 2026-04-25 | 新增规则备注、自动备份、深色模式图标支持 |
| 2.0.1 | 2026-04-22 | 全新界面重构，新增检查更新、导入导出功能 |
| 1.5.0 | 2026-04-22 | 基础功能版本 |
