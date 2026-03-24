import SwiftUI

@main
struct keymapperApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // 加上这一行，禁用掉那个讨厌的“新建 Tab”按钮，并锁定窗口比例
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar) // 也可以考虑隐藏标题栏让它更像工具
    }
}
