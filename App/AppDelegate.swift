import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    static var instance: AppDelegate!

    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var engineMenuItem: NSMenuItem?
    private var cancellable: AnyCancellable?

    override init() {
        super.init()
        AppDelegate.instance = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarIcon()
        _ = MyEngine.shared
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    private func setupMenuBarIcon() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: 14)
        if let button = item.button {
            let icon = Self.loadStatusBarIcon()
            button.image = icon
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()
        menu.delegate = self

        let showItem = NSMenuItem(title: NSLocalizedString("show.window", comment: ""), action: #selector(Self.showMainWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        let engineItem = NSMenuItem(title: NSLocalizedString("pause.engine", comment: ""), action: #selector(Self.toggleEngine), keyEquivalent: "")
        engineItem.target = self
        menu.addItem(engineItem)
        engineMenuItem = engineItem

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: NSLocalizedString("quit.app", comment: ""), action: #selector(Self.quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu

        statusItem = item
        
        updateStatusBarIconAlpha()
        
        cancellable = MyEngine.shared.$isPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBarIconAlpha()
            }
    }
    
    private func updateStatusBarIconAlpha() {
        statusItem?.button?.alphaValue = MyEngine.shared.isPaused ? 0.5 : 1.0
    }
    
    @objc func toggleEngine() {
        MyEngine.shared.toggle()
    }

    @objc func showMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        } else if let window = NSApplication.shared.windows.first(where: { $0.contentView != nil && !$0.isSheet }) {
            mainWindow = window
            window.delegate = self
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    func setMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: "setting_hide_dock") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApplication.shared.setActivationPolicy(.accessory)
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let item = engineMenuItem {
            var title = MyEngine.shared.isPaused ? NSLocalizedString("resume.engine", comment: "") : NSLocalizedString("pause.engine", comment: "")
            if let hk = MyEngine.shared.pauseHotkey {
                title += MyMap.getName(hk.0, hk.1)
            }
            item.title = title
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    private static let iconSize: CGFloat = 22
    
    private static func loadStatusBarIcon() -> NSImage {
        if let image = NSImage(named: "StatusBarIcon") {
            image.size = NSSize(width: iconSize, height: iconSize)
            image.isTemplate = true
            return image
        }
        
        return createDefaultIcon()
    }
    
    private static func createDefaultIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: iconSize, height: iconSize))
        image.lockFocus()
        
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 2, y: 9))
        path.line(to: NSPoint(x: 8, y: 3))
        path.line(to: NSPoint(x: 14, y: 9))
        
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.black.setStroke()
        path.stroke()
        
        image.unlockFocus()
        image.isTemplate = true

        return image
    }
}
