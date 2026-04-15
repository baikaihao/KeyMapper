# Tasks

- [x] Task 1: 在 AppDelegate 中添加暂停状态监听
  - [x] SubTask 1.1: 添加 `cancellable` 属性存储 Combine 订阅
  - [x] SubTask 1.2: 在 `setupMenuBarIcon()` 中订阅 `MyEngine.shared.$isPaused`，当值变化时更新图标透明度
  - [x] SubTask 1.3: 创建 `updateStatusBarIconAlpha()` 方法，根据 `isPaused` 状态设置 `statusItem?.button?.alphaValue`（暂停时 0.5，运行时 1.0）

# Task Dependencies
- 无依赖
