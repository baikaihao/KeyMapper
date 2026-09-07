# Changelog

All notable changes to KeyMapper will be documented in this file.

## KeyMapper 2.3.4

### 更新内容

- 新增键盘选择器对左侧/右侧 Option 和 Command 的选择。
- 录制、规则保存、导入导出、规则显示及运行时匹配均支持修饰键侧别。
- 映射输出会发送对应物理侧别的修饰键事件，修复右侧 Option+C 等场景被系统输入为特殊字符的问题。
- 旧规则和旧配置继续按任意侧兼容。
- 移除不需要的 F1-F12、反引号、向前删除、Home/End、Page Up/Page Down 和数字键盘选择项。
- 弹窗提示设置中的“显示行为”移至页面首位，“启用弹窗提示”作为第一项。

## KeyMapper 2.3.4

### What's Changed

- Added left/right side selection for Option and Command in the key picker.
- Added modifier-side support to recording, rule persistence, import/export, rule display, and runtime matching.
- Mapped output now sends the selected physical modifier key events, fixing cases such as right Option+C being interpreted as a special character by macOS.
- Existing rules and configuration files remain backward-compatible and continue to match any physical side when no side is specified.
- Removed unsupported key picker entries for F1-F12, grave accent, Forward Delete, Home/End, Page Up/Page Down, and the numeric keypad.
- Moved the popup alert “Display Behavior” section to the top of its settings page, with “Enable Popup Alerts” as the first item.

---

## KeyMapper 2.3.3

### 更新内容

- 新增弹窗提示总开关：可一键关闭全部映射触发提示，关闭时会同步收起当前提示。
- 优化全局黑名单管理：新增独立黑名单页面，支持查看应用数量、从运行中的应用快速添加，以及从访达选择应用。
- 提升配置导入安全性：导入前会检查配置版本、格式、规则数量、键码、备注及黑名单，并在覆盖当前配置前请求确认。
- 加强配置数据保护：导入前会自动备份当前配置；校验、备份或保存失败时不会修改现有设置。导入、导出和备份统一使用版本化格式及原子写入。
- 提升自动备份可靠性：应用启动后会恢复备份计划，备份改为后台串行执行，并可在设置页查看进度、下次备份时间和最近错误。
- 提升按键监听稳定性：监听被系统临时禁用、辅助功能权限变化或事件端口失效后，会自动检测并恢复映射。
- 优化暂停快捷键与录制流程：支持更改、取消和恢复默认快捷键；离开页面或窗口失焦时会自动结束录制。
- 修复监听恢复时可能遗留目标按键或修饰键状态、长按暂停快捷键反复切换、窗口意外抢占焦点等问题。

## KeyMapper 2.3.3

### What's Changed

- Added a popup alert master switch that disables all mapping notifications and dismisses currently visible alerts.
- Improved global blacklist management with a dedicated page, app counts, quick selection from running apps, and Finder-based app selection.
- Improved configuration import safety by validating the version, structure, rule count, key codes, notes, and blacklists before asking for overwrite confirmation.
- Strengthened configuration data protection with an automatic pre-import backup. Existing settings remain unchanged if validation, backup, or persistence fails. Import, export, and backup now use a shared versioned format with atomic writes.
- Improved automatic backup reliability with persistent scheduling, serial background execution, progress indicators, the next backup time, and the latest error status.
- Improved keyboard listener reliability with automatic health checks and recovery after system disablement, accessibility permission changes, or event port failures.
- Improved pause hotkey and recording workflows with explicit change, cancel, and restore-default actions. Recording now ends automatically when leaving the page or losing window focus.
- Fixed stuck target keys or modifiers during listener recovery, repeated pause toggles while holding the hotkey, and unexpected window focus changes.

---

## [2.2.0] - 2026-05-01

### Added
- **按键自定义选择器** / **Key Custom Picker**
  - 提供原生风格的可视化按键选择界面，支持 QWERTY 键盘布局按键网格
  - Native-style visual key picker with QWERTY keyboard layout grid
  - 支持两级按键选择：主按键 + 辅助修饰键（⌘⌃⌥⇧），辅助键可动态扩展任意数量
  - Two-level key selection: main key + auxiliary modifiers, dynamically extensible
  - 选择器状态与当前按键组合实时同步，打开时准确显示对应选项
  - Picker state syncs with current key combination, displays accurate options on open
- **规则按键编辑功能** / **Rule Key Editing**
  - 规则列表中每条规则的源键和目标键旁新增编辑按钮，可直接修改已保存的按键组合
  - Edit buttons next to source and target keys in rules list for direct key modification
  - 修改完成后实时更新规则信息显示
  - Real-time rule display update after modification
- **登录时启动状态同步** / **Launch at Login State Sync**
  - App 启动时自动读取系统 SMAppService 实际状态，修正 UserDefaults 中的设置值
  - App reads actual SMAppService system status on launch and corrects UserDefaults
  - 解决因数据迁移、iCloud 同步等原因导致的设置与系统状态不一致问题
  - Resolves inconsistency between settings and system state caused by data migration or iCloud sync

### Changed
- **录制兼容性优化** / **Recording Compatibility**
  - 重写按键录制逻辑，彻底消除旧版本 macOS 上录制时的系统蜂鸣声
  - Rewrote key recording logic to eliminate system beep sounds on older macOS versions
  - 优化 NSView 响应链处理，确保录制框正确获取第一响应者状态
  - Optimized NSView responder chain to ensure recording box properly acquires first responder status
- **登录自启静默启动** / **Silent Launch at Login**
  - 勾选"登录时启动"后，开机自启时不再弹出应用窗口，App 静默运行在菜单栏
  - With "Launch at Login" enabled, app no longer shows window on startup, runs silently in menu bar
  - 用户可通过菜单栏图标随时手动打开窗口
  - Users can manually open window via menu bar icon at any time
- **代码注释规范化** / **Code Documentation**
  - 为所有源代码文件添加标准化注释，提升代码可读性和可维护性
  - Added standardized comments to all source code files for improved readability

### Fixed
- **按键选择器关闭问题** / **Key Picker Close Issue**
  - 修复新增映射时按键选择器点击确认后未自动关闭的问题
  - Fixed key picker not closing automatically after confirming when adding new mapping
- **按键选择器状态重置** / **Key Picker State Reset**
  - 修复录制栏内容为空时按键选择器仍保留上一次选择结果的问题
  - Fixed key picker retaining previous selection when recording area is empty
  - 选择器现在在录制栏为空时自动重置为初始无选中状态
  - Picker now resets to empty state when recording area is cleared

---

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
| 2.3.4 | 2026-09-07 | 支持左右 Option/Command 侧别映射，修复右侧修饰键输入问题，精简按键选择器 / Added left/right Option/Command mapping, fixed right-side modifier input, simplified the key picker |
| 2.3.3 | 2026-08-07 | 新增提示总开关与独立黑名单管理，强化配置、备份及按键监听可靠性 / Added a popup master switch and dedicated blacklist management, with safer configuration, backup, and keyboard monitoring |
| 2.2.0 | 2026-05-01 | 新增按键选择器与规则编辑，修复录制兼容性与登录自启问题 / Added key picker and rule editing, fixed recording compatibility and launch at login issues |
| 2.1.2 | 2026-04-28 | 修复开机启动窗口问题，优化授权引导 / Fixed launch at login window issues, improved authorization guidance |
| 2.1.0 | 2026-04-25 | 新增规则备注、自动备份、深色模式图标支持 / Added rule notes, auto backup, dark mode icons |
| 2.0.1 | 2026-04-22 | 全新界面重构，新增检查更新、导入导出功能 / New UI, update checker, import/export |
| 1.5.0 | 2026-04-22 | 基础功能版本 / Basic feature version |
