import SwiftUI
import AppKit
import Combine

class ToastItem: ObservableObject, Identifiable {
    let id = UUID()
    let text: String
    let displayDuration: Double
    let fadeOutDuration: Double
    @Published var isFading: Bool = false

    init(text: String, displayDuration: Double, fadeOutDuration: Double) {
        self.text = text
        self.displayDuration = displayDuration
        self.fadeOutDuration = fadeOutDuration
    }
}

class ToastState: ObservableObject {
    @Published var items: [ToastItem] = []
    private var removingIds: Set<UUID> = []
    var style: ToastStyle

    init(style: ToastStyle) {
        self.style = style
    }

    var hasVisibleItems: Bool {
        items.contains { !$0.isFading }
    }

    func addToast(text: String) {
        let item = ToastItem(
            text: text,
            displayDuration: style.displayDuration,
            fadeOutDuration: style.fadeOutDuration
        )
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            withAnimation(.easeIn(duration: 0.15)) {
                self.items.append(item)
            }
            Timer.scheduledTimer(withTimeInterval: item.displayDuration, repeats: false) { [weak self, weak item] _ in
                guard let self = self, let item = item else { return }
                if !item.isFading {
                    withAnimation(.easeOut(duration: item.fadeOutDuration)) {
                        item.isFading = true
                    }
                }
                self.scheduleRemoval(item: item)
            }
        }
    }

    func startFading(item: ToastItem) {
        guard !item.isFading else { return }
        withAnimation(.easeOut(duration: item.fadeOutDuration)) {
            item.isFading = true
        }
        scheduleRemoval(item: item)
    }

    func fadeAll() {
        for item in items where !item.isFading {
            startFading(item: item)
        }
    }

    private func scheduleRemoval(item: ToastItem) {
        guard !removingIds.contains(item.id) else { return }
        removingIds.insert(item.id)
        Timer.scheduledTimer(withTimeInterval: item.fadeOutDuration, repeats: false) { [weak self, weak item] _ in
            guard let self = self, let item = item else { return }
            self.removingIds.remove(item.id)
            withAnimation(.easeIn(duration: 0.15)) {
                self.items.removeAll { $0.id == item.id }
            }
        }
    }
}

class ToastManager {
    static let shared = ToastManager()

    var style: ToastStyle {
        didSet {
            style.saveToDefaults()
            applyWindowLevel()
        }
    }

    private let toastState: ToastState
    private var window: NSPanel?
    private var mouseMonitor: Any?
    private var isObserving = false

    private init() {
        style = ToastStyle().loadFromDefaults()
        toastState = ToastState(style: style)
        start()
    }

    func start() {
        guard !isObserving else { return }
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleMappingTriggered(_:)),
            name: .mappingTriggered, object: nil
        )
        isObserving = true
    }

    private var activeScreen: NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func ensureWindow() {
        let screenFrame = activeScreen.frame

        if let window {
            window.setFrame(screenFrame, display: true)
            window.orderFrontRegardless()
            return
        }

        let w = NSPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        w.level = windowLevel
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false
        w.ignoresMouseEvents = true
        w.contentView = NSHostingView(rootView:
            ToastContainerView(state: toastState)
        )
        w.orderFrontRegardless()
        window = w

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.checkMouseHover()
        }
    }

    private var windowLevel: NSWindow.Level {
        style.alwaysOnTop ? .screenSaver : .floating
    }

    private func applyWindowLevel() {
        window?.level = windowLevel
    }

    private func checkMouseHover() {
        guard toastState.hasVisibleItems, let w = window else { return }
        let screenFrame = w.screen?.frame ?? (NSScreen.main?.frame ?? .zero)
        let screenHeight = screenFrame.height
        let screenWidth = screenFrame.width
        let mouseScreen = NSEvent.mouseLocation
        let mouseInWindow = CGPoint(
            x: mouseScreen.x - screenFrame.minX,
            y: screenFrame.maxY - mouseScreen.y
        )
        let padding: CGFloat = 20
        let itemSpacing: CGFloat = 10
        let style = toastState.style
        let visibleItems = toastState.items.filter { !$0.isFading }
        var yOffset: CGFloat = screenHeight - padding

        for item in visibleItems.reversed() {
            let textWidth = max(CGFloat(item.text.count) * style.fontSize * 0.6 + 24, 80)
            let textHeight = style.fontSize + 20
            yOffset -= textHeight
            let itemRect = CGRect(
                x: screenWidth - textWidth - padding,
                y: yOffset,
                width: textWidth,
                height: textHeight
            )
            if itemRect.contains(mouseInWindow) {
                toastState.fadeAll()
                return
            }
            yOffset -= itemSpacing
        }
    }

    @objc private func handleMappingTriggered(_ notification: Notification) {
        guard let index = notification.userInfo?["index"] as? Int else { return }
        let engine = MyEngine.shared
        guard index < engine.list.count else { return }
        let mapping = engine.list[index]
        let text = style.assembleText(
            fromName: MyMap.getName(mapping.fCode, mapping.fFlags).trimmingCharacters(in: .whitespaces),
            toName: MyMap.getName(mapping.tCode, mapping.tFlags).trimmingCharacters(in: .whitespaces),
            note: mapping.note
        )
        guard !text.isEmpty else { return }
        showToast(text: text)
    }

    func showToast(text: String) {
        ensureWindow()
        toastState.style = style
        toastState.addToast(text: text)
    }

    func previewToast() {
        ensureWindow()
        toastState.style = style
        let sampleText = style.assembleText(fromName: "⌃ A", toName: "⌘ C", note: "复制")
        toastState.addToast(text: sampleText)
    }
}
