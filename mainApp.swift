import SwiftUI
import AppKit

// MARK: - KeyMapper 应用入口
// SwiftUI 应用入口，通过 @NSApplicationDelegateAdaptor 注入 AppDelegate。
// 启动时创建一个空窗口并立即关闭，使应用以纯菜单栏模式运行，
// 而非显示一个可见的文档窗口。

@main
struct KeyMapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .onAppear {
                    // 应用启动后立即关闭 SwiftUI 自动创建的空窗口，
                    // 因为 KeyMapper 使用菜单栏图标 + NSWindow 管理主窗口，
                    // 不需要 SwiftUI 的 WindowGroup 窗口
                    if let window = NSApp.windows.first(where: { $0.contentView?.subviews.first is NSHostingView<EmptyView> }) {
                        window.close()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 0, height: 0)
        .commands {
            // 移除 "New" 菜单项，KeyMapper 不需要新建文档功能
            CommandGroup(replacing: .newItem) { }
        }
    }
}
