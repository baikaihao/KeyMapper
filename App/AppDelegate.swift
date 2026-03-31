import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    static let instance = AppDelegate()
    
    /// 强引用，防止 ARC 释放导致图标消失
    private var statusItem: NSStatusItem?
    
    // MARK: - 菜单栏图标
    
    func setupMenuBarIcon() {
        guard statusItem == nil else { return }
        
        let item = NSStatusBar.system.statusItem(withLength: 14)
        if let button = item.button {
            let icon = Self.loadStatusBarIcon()
            button.image = icon
            button.imagePosition = .imageOnly
        }
        
        let menu = NSMenu()
        
        let showItem = NSMenuItem(title: NSLocalizedString("show.window", comment: ""), action: #selector(Self.toggleWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: NSLocalizedString("quit.app", comment: ""), action: #selector(Self.quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        item.menu = menu
        
        statusItem = item
    }
    
    // MARK: - 窗口操作
    
    @objc func toggleWindow() {
        // 保存当前激活策略
        let currentPolicy = NSApplication.shared.activationPolicy()
        
        // 临时设置为 regular 策略以确保窗口可以显示
        if currentPolicy != .regular {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        
        if let window = NSApplication.shared.windows.first {
            if window.isVisible && !window.isMiniaturized && window.isKeyWindow {
                window.miniaturize(nil)
                // 如果原来的策略不是 regular，恢复它
                if currentPolicy != .regular {
                    NSApplication.shared.setActivationPolicy(currentPolicy)
                }
            } else {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        } else {
            // 如果没有窗口，尝试激活应用程序，这会触发 WindowGroup 创建窗口
            NSApplication.shared.activate(ignoringOtherApps: true)
            // 延迟一下确保窗口被创建
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApplication.shared.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - 图标加载
    
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
