import SwiftUI
import AppKit

@main
struct KeyMapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        let hideDock = UserDefaults.standard.bool(forKey: "setting_hide_dock")
        let policy: NSApplication.ActivationPolicy = hideDock ? .accessory : .regular
        NSApplication.shared.setActivationPolicy(policy)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 750, minHeight: 500)
                .onAppear {
                    appDelegate.setupMenuBarIcon()
                }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
