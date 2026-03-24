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
        if let window = NSApplication.shared.windows.first {
            if window.isVisible && !window.isMiniaturized && window.isKeyWindow {
                window.miniaturize(nil)
            } else {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - 图标加载
    
    private static let iconSize: CGFloat = 16
    
    private static func loadStatusBarIcon() -> NSImage {
        // 尝试从 Asset Catalog 加载
        if let image = NSImage(named: "StatusBarIcon") {
            image.size = NSSize(width: iconSize, height: iconSize)
            image.isTemplate = true
            return image
        }
        
        // 尝试从 Bundle 加载并缩放到菜单栏尺寸
        if let imageURL = Bundle.main.url(forResource: "状态栏", withExtension: "png"),
           let original = NSImage(contentsOf: imageURL) {
            let resized = NSImage(size: NSSize(width: iconSize, height: iconSize))
            resized.lockFocus()
            original.draw(in: NSRect(x: 0, y: 0, width: iconSize, height: iconSize),
                          from: NSRect(origin: .zero, size: original.size),
                          operation: .copy,
                          fraction: 1.0)
            resized.unlockFocus()
            resized.isTemplate = true
            return resized
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
