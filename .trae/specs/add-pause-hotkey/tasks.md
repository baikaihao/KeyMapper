# Tasks

- [x] Task 1: 修改 MyEngine 核心逻辑
  - [x] SubTask 1.1: 新增 `pauseHotkey` 属性（`(keyCode: UInt16, flags: UInt64)?`），从 UserDefaults 加载/保存（key: `setting_pause_hotkey`）
  - [x] SubTask 1.2: 修改 `pause()` 方法，移除 `CGEvent.tapEnable(tap:enable:false)` 调用，仅保留 `isPaused = true`
  - [x] SubTask 1.3: 修改 `resume()` 方法，移除 `CGEvent.tapEnable(tap:enable:true)` 调用，仅保留 `isPaused = false`
  - [x] SubTask 1.4: 修改 CGEvent Tap 回调，在防重入标记检查之后、`isPaused` 判断之前，增加暂停快捷键检测逻辑：匹配时调用 `toggle()` 并返回 `nil` 吞掉事件
  - [x] SubTask 1.5: 新增 `savePauseHotkey()` 和 `loadPauseHotkey()` 方法用于持久化

- [x] Task 2: 设置页面新增快捷键配置 UI
  - [x] SubTask 2.1: 在 `SettingsView` 中新增"暂停快捷键"设置项，包含录制按钮和清除按钮
  - [x] SubTask 2.2: 添加 `KeyLogic` 背景视图到 `SettingsView` 以支持快捷键录制
  - [x] SubTask 2.3: 录制完成后将快捷键写入 `MyEngine.shared.pauseHotkey` 并持久化

- [x] Task 3: 本地化字符串
  - [x] SubTask 3.1: 在 `zh-Hans.lproj/Localizable.strings` 中添加暂停快捷键相关字符串
  - [x] SubTask 3.2: 在 `en.lproj/Localizable.strings` 中添加暂停快捷键相关字符串

# Task Dependencies
- Task 2 依赖 Task 1（需要 `pauseHotkey` 属性和持久化方法）
- Task 3 与 Task 1、Task 2 可并行
