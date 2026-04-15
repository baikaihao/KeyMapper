# 引擎暂停快捷键 Spec

## Why
当前引擎暂停/恢复只能通过菜单栏或主界面按钮操作，不够便捷。用户需要一个全局快捷键来快速切换引擎的暂停/恢复状态，且快捷键可自定义。

## What Changes
- 在 `MyEngine` 的 CGEvent Tap 回调中增加暂停快捷键检测逻辑，优先级高于映射规则和暂停状态判断
- 修改 `pause()` / `resume()` 方法，不再禁用/启用 CGEvent Tap，仅通过 `isPaused` 标志控制映射逻辑的放行
- 新增 `pauseHotkey` 属性（类型 `(keyCode: UInt16, flags: UInt64)?`），持久化到 UserDefaults
- 在设置页面新增"暂停快捷键"配置项，支持录制自定义快捷键和清除快捷键
- 复用现有 `RecordRow` 组件实现快捷键录制
- 新增本地化字符串

## Impact
- Affected code: `MyEngine.swift`（核心回调逻辑、暂停/恢复方法）、`SettingsView.swift`（新增快捷键设置 UI）、`ContentView.swift`（无需修改，状态条已自动响应 `isPaused` 变化）、本地化文件
- Affected behavior: 引擎暂停时 CGEvent Tap 不再被禁用，而是保持运行仅跳过映射逻辑，确保暂停快捷键始终可被检测

## ADDED Requirements

### Requirement: 全局暂停快捷键
系统应提供全局快捷键功能，用户按下自定义快捷键时切换引擎的暂停/恢复状态。

#### Scenario: 快捷键切换暂停
- **WHEN** 引擎正在运行且用户按下已配置的暂停快捷键
- **THEN** 引擎进入暂停状态，所有映射规则停止生效，快捷键事件被吞掉不传递给其他应用

#### Scenario: 快捷键切换恢复
- **WHEN** 引擎已暂停且用户按下已配置的暂停快捷键
- **THEN** 引擎恢复运行，映射规则重新生效，快捷键事件被吞掉不传递给其他应用

#### Scenario: 快捷键优先级
- **WHEN** 暂停快捷键与某条映射规则的原键相同
- **THEN** 暂停快捷键优先生效，该映射规则不会被触发

#### Scenario: 未配置快捷键
- **WHEN** 用户未配置暂停快捷键（默认状态）
- **THEN** 快捷键功能不生效，引擎行为与之前一致

### Requirement: 快捷键自定义设置
系统应在设置页面提供暂停快捷键的配置界面，支持录制和清除。

#### Scenario: 录制快捷键
- **WHEN** 用户在设置页面点击录制按钮并按下某个键组合
- **THEN** 该键组合被保存为暂停快捷键，立即生效

#### Scenario: 清除快捷键
- **WHEN** 用户在设置页面点击清除按钮
- **THEN** 暂停快捷键被移除，快捷键功能停止生效

### Requirement: 引擎暂停时保持事件监听
系统在引擎暂停时应保持 CGEvent Tap 运行，仅跳过映射逻辑，以确保暂停快捷键可被检测。

#### Scenario: 暂停状态下快捷键仍可触发
- **WHEN** 引擎处于暂停状态
- **THEN** CGEvent Tap 仍然运行，暂停快捷键仍可被检测并触发恢复操作

## MODIFIED Requirements

### Requirement: 引擎暂停/恢复机制
引擎暂停时不再禁用 CGEvent Tap，改为仅通过 `isPaused` 标志控制映射规则的跳过。回调中的判断顺序为：1) 防重入标记检查 → 2) 暂停快捷键检测 → 3) 暂停状态放行 → 4) 映射规则匹配。
