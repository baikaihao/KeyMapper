# Tasks

- [x] Task 1: 修改 MyEngine 添加黑名单属性和逻辑
  - [x] SubTask 1.1: 新增 `@Published var blacklist: [String]` 属性，存储 bundle identifier 列表，添加 `didSet` 自动保存
  - [x] SubTask 1.2: 新增 `saveBlacklist()` 和 `loadBlacklist()` 方法，使用 UserDefaults 持久化（key: `setting_blacklist`）
  - [x] SubTask 1.3: 在 `init()` 中调用 `loadBlacklist()`
  - [x] SubTask 1.4: 在 CGEvent Tap 回调中，在映射规则匹配之前，检测当前活动应用是否在黑名单中，若在则放行事件

- [x] Task 2: 创建 BlacklistView 视图
  - [x] SubTask 2.1: 创建新文件 `Views/BlacklistView.swift`
  - [x] SubTask 2.2: 显示当前黑名单应用列表（使用应用名称）
  - [x] SubTask 2.3: 添加"添加应用"按钮，使用 `NSOpenPanel` 选择 .app 文件
  - [x] SubTask 2.4: 从选择的 .app 文件中提取 bundle identifier（使用 `Bundle` 或读取 Info.plist）
  - [x] SubTask 2.5: 每个黑名单项显示删除按钮

- [x] Task 3: 在设置页面添加黑名单入口
  - [x] SubTask 3.1: 在设置页面底部添加"管理黑名单"按钮
  - [x] SubTask 3.2: 点击按钮后以 sheet 形式打开 BlacklistView

- [x] Task 4: 本地化字符串
  - [x] SubTask 4.1: 在 `zh-Hans.lproj/Localizable.strings` 中添加黑名单相关字符串
  - [x] SubTask 4.2: 在 `en.lproj/Localizable.strings` 中添加黑名单相关字符串

# Task Dependencies
- Task 2 依赖 Task 1（需要 `blacklist` 属性）
- Task 3 依赖 Task 2（需要 BlacklistView）
- Task 4 与 Task 1、Task 2、Task 3 可并行
