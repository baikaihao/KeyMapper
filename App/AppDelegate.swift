import AppKit
import SwiftUI
import Combine
import ServiceManagement

// MARK: - AppDelegate
// 应用生命周期与菜单栏管理器。
// 职责：
// 1. 创建系统状态栏图标（暂停时半透明显示）
// 2. 创建主窗口（NSWindow + NSHostingView 承载 ContentView）
// 3. 管理菜单栏菜单（显示窗口、暂停/恢复引擎、退出）
// 4. 监听引擎激活状态，按启动策略调度主窗口显示
// 5. 支持 Dock 图标隐藏模式（.accessory 策略）

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {

    // 系统状态栏图标项
    private var statusItem: NSStatusItem?
    // 菜单栏中的"暂停/恢复引擎"菜单项引用，用于动态更新标题
    private var engineMenuItem: NSMenuItem?
    // 应用主窗口
    private var mainWindow: NSWindow?
    // Combine 订阅集合，用于管理 KVO 订阅的生命周期
    private var cancellables = Set<AnyCancellable>()
    // 是否为登录时启动（开机自启模式下不主动弹窗）
    private var isLaunchAtLogin = false

    private enum MainWindowPresentation {
        case appLaunch
        case userRequested
        case engineBecameActive
    }

    // MARK: - 应用生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarIcon()
        // 触发 MyEngine 单例初始化，加载映射规则并启动键盘事件监听
        _ = MyEngine.shared
        // 登录时启动不会打开设置页，因此弹窗提示管理器必须在启动阶段注册监听。
        ToastManager.shared.start()

        syncAndRecordLaunchAtLogin()

        // 根据用户设置决定是否隐藏 Dock 图标
        // .accessory: 仅菜单栏图标，无 Dock 图标
        // .regular: 菜单栏图标 + Dock 图标
        let hideDock = UserDefaults.standard.bool(forKey: "setting_hide_dock")
        NSApp.setActivationPolicy(hideDock ? .accessory : .regular)

        createMainWindow()

        setupEngineObserver()
    }

    // 点击 Dock 图标或重新打开应用时，显示主窗口而非创建新窗口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    static func syncLaunchAtLoginState() {
        let service = SMAppService.mainApp
        let systemEnabled = (service.status == .enabled)
        let userDefaultsKey = "setting_launch_at_login"
        let storedValue = UserDefaults.standard.bool(forKey: userDefaultsKey)

        if systemEnabled != storedValue {
            UserDefaults.standard.set(systemEnabled, forKey: userDefaultsKey)
        }
    }

    private func syncAndRecordLaunchAtLogin() {
        Self.syncLaunchAtLoginState()
        isLaunchAtLogin = UserDefaults.standard.bool(forKey: "setting_launch_at_login")
    }

    // MARK: - 菜单栏图标与菜单

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

        // 监听引擎暂停状态变化，更新状态栏图标透明度
        MyEngine.shared.$isPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBarIconAlpha()
            }
            .store(in: &cancellables)
    }

    // 引擎暂停时图标半透明（0.5），运行时完全不透明（1.0）
    private func updateStatusBarIconAlpha() {
        statusItem?.button?.alphaValue = MyEngine.shared.isPaused ? 0.5 : 1.0
    }

    // MARK: - 主窗口管理

    private func createMainWindow() {
        guard mainWindow == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = "KeyMapper"
        window.titlebarAppearsTransparent = false
        // 关闭窗口时不销毁，仅隐藏，方便再次显示
        window.isReleasedWhenClosed = false
        window.delegate = self

        let hostingView = NSHostingView(rootView: ContentView())
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView

        mainWindow = window
        applyMainWindowLevel(to: window)

        presentMainWindow(.appLaunch)
    }

    private var shouldAutoPresentMainWindow: Bool {
        !UserDefaults.standard.bool(forKey: "setting_hide_dock") && !isLaunchAtLogin
    }

    private func applyMainWindowLevel(to targetWindow: NSWindow? = nil) {
        guard let window = targetWindow ?? mainWindow else { return }
        window.level = .normal
    }

    private func presentMainWindow(_ presentation: MainWindowPresentation) {
        guard let window = mainWindow else { return }
        applyMainWindowLevel(to: window)

        switch presentation {
        case .appLaunch, .engineBecameActive:
            guard shouldAutoPresentMainWindow else { return }
        case .userRequested:
            NSApp.setActivationPolicy(.regular)
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // 监听引擎激活状态变化：
    // - 激活时：窗口恢复普通层级
    // - 未激活时：保持普通窗口层级，仅通过界面内容提醒用户授权
    // 登录自启模式下，即使引擎激活也不主动弹窗，避免打扰用户
    private func setupEngineObserver() {
        MyEngine.shared.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let self = self else { return }
                self.applyMainWindowLevel()
                if isActive {
                    self.presentMainWindow(.engineBecameActive)
                }
            }
            .store(in: &cancellables)
    }

    // 显示主窗口：恢复 Dock 图标、解除最小化、前置窗口
    @objc func showMainWindow() {
        presentMainWindow(.userRequested)
    }

    // MARK: - NSWindowDelegate

    // 关闭按钮行为：仅隐藏窗口而非销毁，并在隐藏 Dock 模式下切换为 .accessory 策略
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)

        if UserDefaults.standard.bool(forKey: "setting_hide_dock") {
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
            }
        }

        return false
    }

    // MARK: - 菜单动作

    @objc func toggleEngine() {
        MyEngine.shared.toggle()
    }

    // 菜单即将显示时，动态更新"暂停/恢复引擎"菜单项的标题和热键提示
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let item = engineMenuItem {
            var title = MyEngine.shared.isPaused
                ? NSLocalizedString("resume.engine", comment: "")
                : NSLocalizedString("pause.engine", comment: "")

            // 如果设置了暂停热键，在标题后追加热键名称
            if let hk = MyEngine.shared.pauseHotkey {
                title += MyMap.getName(hk.0, hk.1)
            }

            item.title = title
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - 状态栏图标加载

    private static let iconSize: CGFloat = 22

    // 优先从 Asset Catalog 加载图标，加载失败则代码绘制默认图标
    private static func loadStatusBarIcon() -> NSImage {
        if let image = NSImage(named: "StatusBarIcon") {
            image.size = NSSize(width: iconSize, height: iconSize)
            image.isTemplate = true
            return image
        }
        return createDefaultIcon()
    }

    // 代码绘制默认状态栏图标：一个向下的箭头（V 形）
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
        // 设为模板图标，系统自动适配明暗模式
        image.isTemplate = true

        return image
    }
}
