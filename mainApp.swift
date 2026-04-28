import SwiftUI
import AppKit

@main
struct KeyMapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .onAppear {
                    if let window = NSApp.windows.first(where: { $0.contentView?.subviews.first is NSHostingView<EmptyView> }) {
                        window.close()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 0, height: 0)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
