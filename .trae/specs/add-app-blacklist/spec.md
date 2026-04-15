# 应用黑名单 Spec

## Why
用户希望在某些特定应用中禁用按键映射功能。例如在终端.app 中输入时，不希望触发按键映射。需要提供应用黑名单功能，让用户可以指定哪些应用中不启用映射。

## What Changes
- 在 `MyEngine` 中新增 `blacklist` 属性（类型 `[String]`，存储应用的 bundle identifier），持久化到 UserDefaults
- 在 CGEvent Tap 回调中，检测当前活动应用（`NSWorkspace.shared.frontmostApplication`），如果其 bundle identifier 在黑名单中，则放行事件不进行映射
- 在设置页面中新增黑名单入口按钮，点击后打开单独的黑名单管理窗口
- 创建单独的 `BlacklistView` 视图用于管理黑名单
- 使用 `NSOpenPanel` 让用户选择应用（.app 文件），自动提取 bundle identifier

## Impact
- Affected code: `MyEngine.swift`（黑名单属性、回调逻辑）、`SettingsView.swift`（黑名单管理 UI）、本地化文件
- Affected behavior: 当焦点在黑名单应用中时，按键映射不生效，事件直接放行

## ADDED Requirements

### Requirement: 应用黑名单
系统应提供应用黑名单功能，当用户焦点在黑名单应用中时，按键映射不生效。

#### Scenario: 黑名单应用中禁用映射
- **WHEN** 当前活动应用的 bundle identifier 在黑名单中
- **THEN** 按键事件直接放行，不进行任何映射处理

#### Scenario: 非黑名单应用中正常映射
- **WHEN** 当前活动应用的 bundle identifier 不在黑名单中
- **THEN** 按键事件正常进行映射处理

#### Scenario: 无法获取活动应用
- **WHEN** 无法获取当前活动应用或其 bundle identifier
- **THEN** 默认进行映射处理（保守策略）

### Requirement: 黑名单管理 UI
设置页面应提供入口打开黑名单管理窗口，支持添加和删除黑名单应用。

#### Scenario: 打开黑名单管理窗口
- **WHEN** 用户在设置页面点击"管理黑名单"按钮
- **THEN** 打开单独的黑名单管理窗口

#### Scenario: 添加应用到黑名单
- **WHEN** 用户点击"添加应用"按钮
- **THEN** 弹出文件选择器，用户选择 .app 文件后，提取其 bundle identifier 并添加到黑名单

#### Scenario: 从黑名单移除应用
- **WHEN** 用户点击黑名单列表中某应用的删除按钮
- **THEN** 该应用从黑名单中移除

#### Scenario: 显示黑名单应用名称
- **WHEN** 黑名单中有应用
- **THEN** 显示应用的本地化名称（而非 bundle identifier）
