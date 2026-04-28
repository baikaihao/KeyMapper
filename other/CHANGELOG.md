# Changelog

All notable changes to KeyMapper will be documented in this file.

## [2.1.2] - 2026-04-28

### Added
- **开机启动窗口修复** / **Launch at Login Window Fix**
  - 完全重写窗口管理逻辑，解决开机启动后窗口侧边栏布局错乱问题
  - Completely rewrote window management logic to fix sidebar layout issues after launch at login
  - 窗口现在由 AppDelegate 统一管理，确保所有启动场景下窗口行为一致
  - Windows are now managed by AppDelegate to ensure consistent behavior across all launch scenarios

### Changed
- **授权引导优化** / **Authorization Guidance Improvements**
  - 侧边栏未授权状态改为可点击按钮，点击直接跳转设置页面
  - Sidebar unauthorized status changed to clickable button that navigates to Settings
  - 设置页面辅助功能授权描述更详细，提供完整的操作步骤指引
  - More detailed accessibility permission description in Settings with complete step-by-step instructions
  - 中英文本地化文本优化
  - Optimized Chinese and English localization text

### Fixed
- **窗口生命周期管理** / **Window Lifecycle Management**
  - 修复 SwiftUI WindowGroup 与手动 NSWindow 冲突导致的布局问题
  - Fixed layout issues caused by conflicts between SwiftUI WindowGroup and manual NSWindow
  - 移除 WindowGroup 自动窗口创建，完全由 AppDelegate 控制
  - Removed WindowGroup automatic window creation, now fully controlled by AppDelegate
  - 统一所有场景（开机启动、手动启动、Dock点击）的窗口创建逻辑
  - Unified window creation logic for all scenarios (launch at login, manual launch, Dock click)

---

## [2.1.0] - 2026-04-25

### Added
- **规则备注功能** / **Rule Notes**: 为每条映射规则添加备注说明，方便记忆和管理 / Add notes to each mapping rule for easier management
- **自动备份功能** / **Auto Backup**:
  - 支持定时自动备份映射规则 / Scheduled automatic backup of mapping rules
  - 可设置备份间隔（1-14天）/ Configurable backup interval (1-14 days)
  - 可设置最大备份数量（1-20个），超过自动删除最旧的备份 / Max backup count (1-20), auto-deletes oldest
  - 默认备份路径为 `~/Documents/KeyMapperRules` / Default backup path: `~/Documents/KeyMapperRules`
  - 支持自定义备份路径 / Custom backup path support
  - 一键打开备份文件夹 / One-click open backup folder
- **深色模式图标** / **Dark Mode Icons**: APP图标和关于页面图标支持深色模式自动切换 / App and About page icons support automatic dark mode switching
- **未授权提示优化** / **Unauthorized Prompt**: 侧边栏未授权状态新增"请授权后重启"提示 / Added "Please restart after authorization" prompt in sidebar

### Changed
- **导入导出优化** / **Import/Export**: 文件选择器默认打开备份路径 / File picker now defaults to backup path
- **数据兼容性** / **Data Compatibility**: 优化数据模型，支持向后兼容旧版本配置 / Optimized data model for backward compatibility

### Fixed
- **数据迁移** / **Data Migration**: 修复添加备注字段后旧数据兼容性问题 / Fixed old data compatibility after adding notes field

---

## [2.0.1] - 2026-04-22

### Added
- **全新原生 macOS 界面** / **New Native macOS Interface**: 采用 NavigationSplitView 侧边栏导航布局 / NavigationSplitView sidebar navigation layout
- **检查更新功能** / **Update Checker**: 通过 GitHub Releases API 检查新版本 / Check for new versions via GitHub Releases API
- **导入导出功能** / **Import/Export**: 支持备份和恢复映射规则为 JSON 文件 / Backup and restore mapping rules as JSON files
- **关于页面** / **About Page**: 显示版本信息、许可证和技术支持链接 / Display version info, license, and support links
- **GitHub 图标** / **GitHub Icon**: 关于页面使用 GitHub 官方图标 / Official GitHub icon on About page

### Changed
- **界面重构** / **UI Refactoring**: 完全重新设计 UI，采用原生 macOS 窗口风格 / Complete UI redesign with native macOS window style
- **规则列表** / **Rules List**: 四列布局（原键、映射为、启用、操作），隔行变色提高可读性 / Four-column layout with alternating row colors
- **录制按键** / **Key Recording**: 点击范围扩大至整个按键块区域 / Expanded tap area to entire key block
- **垃圾桶图标** / **Trash Icon**: 全局改为红色，更易识别 / Changed to red globally for better visibility
- **版本号** / **Version Number**: 从 Info.plist 动态读取 / Dynamically read from Info.plist

### Fixed
- **窗口显示** / **Window Display**: 修复菜单栏"显示窗口"显示旧样式小窗口的问题 / Fixed menu bar "Show Window" displaying old-style small window
- **规则列表滚动** / **Rules List Scrolling**: 修复底部规则被录制区域遮挡的问题 / Fixed bottom rules being obscured by recording area
- **导出导入** / **Export/Import**: 完善错误处理和成功提示 / Improved error handling and success notifications

---

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
| 2.1.2 | 2026-04-28 | 修复开机启动窗口问题，优化授权引导 / Fixed launch at login window issues, improved authorization guidance |
| 2.1.0 | 2026-04-25 | 新增规则备注、自动备份、深色模式图标支持 / Added rule notes, auto backup, dark mode icons |
| 2.0.1 | 2026-04-22 | 全新界面重构，新增检查更新、导入导出功能 / New UI, update checker, import/export |
| 1.5.0 | 2026-04-22 | 基础功能版本 / Basic feature version |
