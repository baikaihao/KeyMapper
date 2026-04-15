# Tasks

- [x] Task 1: 修改 MyEngine.loadPauseHotkey() 添加默认快捷键
  - [x] SubTask 1.1: 在 `loadPauseHotkey()` 方法中，当 UserDefaults 无保存值时，设置 `pauseHotkey` 为 `(keyCode: 6, flags: 0x120000)`（即 ⇧⌘Z）

- [x] Task 2: 修改 AppDelegate.menuNeedsUpdate() 显示快捷键
  - [x] SubTask 2.1: 在 `menuNeedsUpdate()` 中，当 `MyEngine.shared.pauseHotkey` 不为 nil 时，使用 `MyMap.getName()` 获取快捷键显示字符串，追加到菜单项标题后

- [x] Task 3: 修改 SettingsView 清除按钮为恢复默认
  - [x] SubTask 3.1: 将快捷键旁的 xmark 清除按钮改为"恢复默认"按钮，点击后设置 `engine.pauseHotkey = (keyCode: 6, flags: 0x120000)`

# Task Dependencies
- Task 1、Task 2、Task 3 相互独立，可并行
