import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private var engineMenuItem: NSMenuItem?
    private var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarIcon()
        _ = MyEngine.shared

        let hideDock = UserDefaults.standard.bool(forKey: "setting_hide_dock")
        NSApp.setActivationPolicy(hideDock ? .accessory : .regular)

        createMainWindow()

        setupEngineObserver()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    // MARK: - Menu Bar

    private func setupMenuBarIcon() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: 22)

        if let button = item.button {
            button.image = Self.loadStatusBarIcon()
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()
        menu.delegate = self

        let showItem = NSMenuItem(
            title: NSLocalizedString("show.window", comment: ""),
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        let engineItem = NSMenuItem(
            title: NSLocalizedString("pause.engine", comment: ""),
            action: #selector(toggleEngine),
            keyEquivalent: ""
        )
        engineItem.target = self
        menu.addItem(engineItem)
        engineMenuItem = engineItem

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: NSLocalizedString("quit.app", comment: ""),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item

        updateStatusBarIconAlpha()

        MyEngine.shared.$isPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBarIconAlpha()
            }
            .store(in: &cancellables)
    }

    private func updateStatusBarIconAlpha() {
        statusItem?.button?.alphaValue = MyEngine.shared.isPaused ? 0.5 : 1.0
    }

    // MARK: - Window Management

    private func createMainWindow() {
        guard mainWindow == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = "KeyMapper"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.delegate = self

        let hostingView = NSHostingView(rootView: ContentView())
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView

        if !MyEngine.shared.isActive {
            window.level = .floating
        }

        mainWindow = window

        let hideDock = UserDefaults.standard.bool(forKey: "setting_hide_dock")
        if !hideDock {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func setupEngineObserver() {
        MyEngine.shared.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let window = self?.mainWindow else { return }
                window.level = isActive ? .normal : .floating
                if isActive {
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                }
            }
            .store(in: &cancellables)
    }

    @objc func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)

        if UserDefaults.standard.bool(forKey: "setting_hide_dock") {
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
            }
        }

        return false
    }

    // MARK: - Menu Actions

    @objc func toggleEngine() {
        MyEngine.shared.toggle()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let item = engineMenuItem {
            var title = MyEngine.shared.isPaused
                ? NSLocalizedString("resume.engine", comment: "")
                : NSLocalizedString("pause.engine", comment: "")

            if let hk = MyEngine.shared.pauseHotkey {
                title += MyMap.getName(hk.0, hk.1)
            }

            item.title = title
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Icon

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
