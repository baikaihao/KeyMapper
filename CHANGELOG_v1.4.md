# KeyMapper v1.4 更新说明

## 新增功能

### 1. 引擎暂停快捷键
- **全局快捷键支持**：新增可自定义的暂停/恢复引擎快捷键
- **默认快捷键**：首次启动自动设置为 ⇧⌘Z（Shift+Command+Z）
- **快捷键录制**：在设置页面可直接录制自定义快捷键
- **恢复默认**：一键恢复默认快捷键设置

### 2. 状态栏图标视觉反馈
- **暂停状态指示**：引擎暂停时状态栏图标透明度降低至 50%，直观显示当前状态
- **实时更新**：图标状态随引擎暂停/恢复实时变化

### 3. 菜单栏快捷键显示
- **快捷键提示**：菜单栏的"暂停引擎"/"恢复引擎"菜单项现在显示当前配置的快捷键
- 例如："暂停引擎    ⇧ ⌘ Z"

### 4. 应用黑名单
- **应用级禁用**：指定特定应用中不启用按键映射
- **黑名单管理**：新增独立的黑名单管理窗口
  - 从应用程序文件夹选择应用添加
  - 显示应用本地化名称
  - 支持删除黑名单中的应用
- **自动生效**：当焦点切换到黑名单应用时，按键映射自动禁用

## 改进

- 引擎暂停时保持事件监听，确保暂停快捷键始终可触发
- 暂停快捷键优先级高于映射规则，避免冲突
- 设置页面布局优化，新增黑名单入口

## 修复

- 无

---

# KeyMapper v1.4 Release Notes

## New Features

### 1. Engine Pause Hotkey
- **Global Hotkey Support**: Added customizable hotkey to pause/resume the engine
- **Default Hotkey**: Automatically set to ⇧⌘Z (Shift+Command+Z) on first launch
- **Hotkey Recording**: Record custom hotkeys directly in Settings
- **Reset to Default**: One-click restore to default hotkey

### 2. Status Bar Icon Visual Feedback
- **Pause State Indicator**: Status bar icon dims to 50% opacity when engine is paused
- **Real-time Updates**: Icon state changes instantly with engine pause/resume

### 3. Menu Bar Hotkey Display
- **Shortcut Hint**: Menu bar items now show the current configured hotkey
- Example: "Pause Engine    ⇧ ⌘ Z"

### 4. App Blacklist
- **App-level Disabling**: Disable key mapping in specific applications
- **Blacklist Management**: New dedicated blacklist management window
  - Add apps from Applications folder
  - Display localized app names
  - Remove apps from blacklist
- **Auto-activation**: Key mapping automatically disabled when switching to blacklisted apps

## Improvements

- Engine maintains event monitoring when paused, ensuring pause hotkey always works
- Pause hotkey takes priority over mapping rules to prevent conflicts
- Settings page layout optimized with blacklist entry point

## Bug Fixes

- None
