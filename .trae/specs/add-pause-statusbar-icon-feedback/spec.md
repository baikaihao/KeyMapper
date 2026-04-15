# 状态栏图标暂停状态视觉反馈 Spec

## Why
当前引擎暂停时，状态栏图标没有任何视觉变化，用户无法直观地从图标判断引擎是否处于暂停状态。需要在引擎暂停时让状态栏图标有视觉反馈。

## What Changes
- 在 `AppDelegate` 中监听 `MyEngine.shared.isPaused` 的变化
- 当引擎暂停时，降低状态栏图标的不透明度（alpha 值设为 0.5）
- 当引擎恢复运行时，恢复图标的不透明度（alpha 值设为 1.0）

## Impact
- Affected code: `AppDelegate.swift`（添加 Combine 订阅、图标透明度更新逻辑）
- Affected behavior: 引擎暂停时状态栏图标变淡，用户可直观判断引擎状态

## ADDED Requirements

### Requirement: 状态栏图标暂停状态视觉反馈
系统应在引擎暂停时改变状态栏图标的外观，提供视觉反馈。

#### Scenario: 引擎暂停时图标变淡
- **WHEN** 引擎进入暂停状态
- **THEN** 状态栏图标的不透明度降低为 0.5，呈现变淡效果

#### Scenario: 引擎恢复时图标恢复正常
- **WHEN** 引擎从暂停状态恢复运行
- **THEN** 状态栏图标的不透明度恢复为 1.0，呈现正常亮度

#### Scenario: 应用启动时图标状态正确
- **WHEN** 应用启动时引擎处于暂停状态（虽然默认不暂停）
- **THEN** 状态栏图标的不透明度应正确反映当前引擎状态
