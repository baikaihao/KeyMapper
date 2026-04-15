# 暂停快捷键默认值与菜单栏显示 Spec

## Why
当前暂停快捷键默认为空，用户需要手动设置才能使用；且菜单栏的"暂停引擎"/"恢复引擎"项未显示快捷键，用户无法直观了解快捷键设置。快捷键不可为空，应默认设置为 ⇧⌘Z。

## What Changes
- 修改 `loadPauseHotkey()` 方法，当 UserDefaults 中无已保存的快捷键时，设置默认值为 ⇧⌘Z（Shift+Command+Z，keyCode=6, flags=0x120000）
- 修改 `AppDelegate.menuNeedsUpdate()` 方法，在"暂停引擎"/"恢复引擎"菜单项标题后追加快捷键显示字符串（复用 `MyMap.getName`）
- 修改 `SettingsView` 中的清除按钮为"恢复默认"按钮，点击后将快捷键重置为 ⇧⌘Z 而非 nil

## Impact
- Affected code: `MyEngine.swift`（loadPauseHotkey 默认值逻辑）、`AppDelegate.swift`（menuNeedsUpdate 菜单标题逻辑）、`SettingsView.swift`（清除按钮改为恢复默认）
- Affected behavior: 首次启动时暂停快捷键自动设为 ⇧⌘Z；菜单栏菜单项标题会显示当前快捷键；设置页面不再允许清空快捷键

## MODIFIED Requirements

### Requirement: 暂停快捷键默认值
暂停快捷键的默认值从 `nil`（无快捷键）改为 `⇧⌘Z`（Shift+Command+Z）。快捷键不可为空。当 UserDefaults 中不存在已保存的快捷键时，`loadPauseHotkey()` 应设置默认值。

#### Scenario: 首次启动
- **WHEN** 用户首次启动应用（UserDefaults 中无 `setting_pause_hotkey` 键）
- **THEN** 暂停快捷键自动设为 ⇧⌘Z，用户可立即使用

#### Scenario: 已有自定义快捷键
- **WHEN** 用户之前已保存过自定义快捷键
- **THEN** 加载已保存的快捷键，不使用默认值

#### Scenario: 用户恢复默认后重启
- **WHEN** 用户在设置中点击"恢复默认"将快捷键重置为 ⇧⌘Z，然后重启应用
- **THEN** 加载 ⇧⌘Z

### Requirement: 菜单栏显示快捷键
菜单栏的"暂停引擎"/"恢复引擎"菜单项应显示当前配置的快捷键。

#### Scenario: 已配置快捷键
- **WHEN** 暂停快捷键已配置（如 ⇧⌘Z）
- **THEN** 菜单项标题显示为"暂停引擎    ⇧ ⌘ Z"或"恢复引擎    ⇧ ⌘ Z"

#### Scenario: 快捷键为 nil（理论上不会出现）
- **WHEN** 暂停快捷键未配置
- **THEN** 菜单项标题仅显示"暂停引擎"或"恢复引擎"，不追加快捷键字符串

### Requirement: 设置页面恢复默认
设置页面的快捷键配置区域应提供"恢复默认"按钮而非"清除"按钮，点击后将快捷键重置为 ⇧⌘Z。

#### Scenario: 恢复默认
- **WHEN** 用户点击"恢复默认"按钮
- **THEN** 快捷键被重置为 ⇧⌘Z
