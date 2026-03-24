import SwiftUI
import AppKit

@main
struct KeyMapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // 启动时检查隐藏 Dock 设置
        let hideDock = UserDefaults.standard.bool(forKey: "setting_hide_dock")
        let policy: NSApplication.ActivationPolicy = hideDock ? .accessory : .regular
        NSApplication.shared.setActivationPolicy(policy)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    appDelegate.setupMenuBarIcon()
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
