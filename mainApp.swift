import SwiftUI
import AppKit

// MARK: - KeyMapper 应用入口
// SwiftUI 应用入口，通过 @NSApplicationDelegateAdaptor 注入 AppDelegate。
// 不声明 WindowGroup，避免 SwiftUI 在启动时创建额外的隐藏窗口。

@main
struct KeyMapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            // 移除 "New" 菜单项，KeyMapper 不需要新建文档功能
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appSettings) { }
        }
    }
}
