import SwiftUI
import Combine
import AppKit
import ServiceManagement

// ============ 模型部分 ============
struct MyMap: Identifiable, Codable {
    var id = UUID()
    var fCode: UInt16
    var fFlags: UInt64
    var tCode: UInt16
    var tFlags: UInt64
    var isOn: Bool = true
    
    static func getName(_ c: UInt16, _ f: UInt64) -> String {
        var s = " "
        if (f & 0x40000) != 0 { s += "⌃ " }
        if (f & 0x80000) != 0 { s += "⌥ " }
        if (f & 0x20000) != 0 { s += "⇧ " }
        if (f & 0x100000) != 0 { s += "⌘ " }
        
        let keyMap: [UInt16: String] = [
            0:  "A ", 1:  "S ", 2:  "D ", 3:  "F ", 4:  "H ", 5:  "G ", 6:  "Z ", 7:  "X ", 8:  "C ", 9:  "V ",
            11:  "B ", 12:  "Q ", 13:  "W ", 14:  "E ", 15:  "R ", 16:  "Y ", 17:  "T ", 18:  "1 ", 19:  "2 ",
            20:  "3 ", 21:  "4 ", 22:  "6 ", 23:  "5 ", 24:  "= ", 25:  "9 ", 26:  "7 ", 27:  "-", 28:  "8 ",
            29:  "0 ", 30:  "] ", 31:  "I ", 32:  "U ", 33:  "[ ", 34:  "O ", 35:  "P ", 37:  "L ", 38:  "J ",
            39:  "' ", 40:  "K ", 41:  "; ", 42:  "\\ ", 43:  ", ", 44:  "/ ", 45:  "N ", 46:  "M ", 47:  ". ",
            49:  "Space ", 36:  "↩ ", 51:  "⌫ ", 53:  "Esc ", 48:  "Tab ",
            123:  "← ", 124:  "→ ", 125:  "↓ ", 126:  "↑ "
        ]
        
        return s + (keyMap[c] ?? "K\(c) ")
    }
}

// ============ 引擎部分 ============
class MyEngine: ObservableObject {
    static let shared = MyEngine()
    @Published var list: [MyMap] = [] { didSet { save() } }
    @Published var isActive: Bool = false
    
    private var tap: CFMachPort?
    private var retryTimer: Timer?
    
    init() {
        load()
        start()
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "saved_maps")
        }
    }
    
    func load() {
        if let data = UserDefaults.standard.data(forKey: "saved_maps"),
           let decoded = try? JSONDecoder().decode([MyMap].self, from: data) {
            self.list = decoded
        }
    }
    
    func start() {
        retryTimer?.invalidate()
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { (proxy, type, event, _) -> Unmanaged<CGEvent>? in
            let c = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let f = event.flags.rawValue
            
            if event.getIntegerValueField(.eventSourceUserData) == 12345 {
                return Unmanaged.passRetained(event)
            }
            
            let modifierMask: UInt64 = 0x40000 | 0x80000 | 0x20000 | 0x100000
            let currentModifiers = f & modifierMask
            
            if let m = MyEngine.shared.list.first(where: {
                $0.isOn && $0.fCode == c && ($0.fFlags & modifierMask) == currentModifiers
            }) {
                let internalSource = CGEventSource(stateID: .combinedSessionState)
                if let e = CGEvent(keyboardEventSource: internalSource, virtualKey: m.tCode, keyDown: type == .keyDown) {
                    e.flags = CGEventFlags(rawValue: m.tFlags)
                    e.setIntegerValueField(.eventSourceUserData, value: 12345)
                    e.tapPostEvent(proxy)
                    return nil
                }
            }
            return Unmanaged.passRetained(event)
        }
        
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: nil
        )
        
        if let t = tap {
            let s = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
            CGEvent.tapEnable(tap: t, enable: true)
            self.isActive = true
        } else {
            self.isActive = false
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.start()
            }
        }
    }
}

// ============ 主界面 ============
struct ContentView: View {
    @StateObject var engine = MyEngine.shared
    @State private var tmpTrig: (UInt16, UInt64)?
    @State private var tmpTarg: (UInt16, UInt64)?
    @State private var isRec1 = false
    @State private var isRec2 = false
    @State private var showSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部状态条 + 设置按钮
            HStack {
                Circle()
                    .fill(engine.isActive ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(engine.isActive ? "引擎运行中" : "等待授权...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(engine.isActive ? .green : .red)
                
                Spacer()
                
                // 设置按钮
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("设置")
                
                // 未授权时显示开启按钮
                if !engine.isActive {
                    Button("去开启") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(engine.isActive ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
            
            Divider()
            
            // 主内容区
            HStack(alignment: .top, spacing: 0) {
                // 左侧：新建映射区
                VStack(spacing: 15) {
                    Text("新建映射")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        RecordRow(isRec: $isRec1, val: $tmpTrig, title: "按下原键: ") {
                            if isRec1 { isRec2 = false }
                        }
                        RecordRow(isRec: $isRec2, val: $tmpTarg, title: "映射为: ") {
                            if isRec2 { isRec1 = false }
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(8)
                    
                    Button(action: addMapping) {
                        Label("保存规则", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(tmpTrig == nil || tmpTarg == nil)
                }
                .padding()
                .frame(width: 200)
                
                Divider()
                
                // 右侧：规则列表区
                VStack(alignment: .leading, spacing: 0) {
                    Text("已保存规则")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding([.leading, .top], 10)
                    
                    List {
                        ForEach(engine.list) { m in
                            HStack(spacing: 8) {
                                Text(MyMap.getName(m.fCode, m.fFlags))
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 50, alignment: .leading)
                                
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Text(MyMap.getName(m.tCode, m.tFlags))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.blue)
                                    .frame(width: 50, alignment: .leading)
                                
                                Spacer()
                                
                                // 删除按钮
                                Button(action: { deleteById(m.id) }) {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                                
                                // 启用开关
                                Toggle(" ", isOn: Binding(
                                    get: { m.isOn },
                                    set: { val in
                                        if let idx = engine.list.firstIndex(where: { $0.id == m.id }) {
                                            engine.list[idx].isOn = val
                                        }
                                    }
                                ))
                                .toggleStyle(.switch)
                                .scaleEffect(0.7)
                                .labelsHidden()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.inset)
                }
                .frame(minWidth: 250, minHeight: 280)
            }
        }
        .fixedSize()
        .background(KeyLogic(r1: $isRec1, r2: $isRec2, t1: $tmpTrig, t2: $tmpTarg))
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
    
    func addMapping() {
        if let a = tmpTrig, let b = tmpTarg {
            engine.list.append(MyMap(fCode: a.0, fFlags: a.1, tCode: b.0, tFlags: b.1))
            tmpTrig = nil
            tmpTarg = nil
        }
    }
    
    func deleteById(_ id: UUID) {
        engine.list.removeAll { $0.id == id }
    }
}

// ============ 辅助组件：录制行 ============
struct RecordRow: View {
    @Binding var isRec: Bool
    @Binding var val: (UInt16, UInt64)?
    let title: String
    var onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            HStack(spacing: 6) {
                Button(action: { isRec.toggle(); onToggle() }) {
                    Text(isRec ? "等待输入..." : (val == nil ? "点击录制" : MyMap.getName(val!.0, val!.1)))
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(isRec ? Color.red.opacity(0.1) : Color.blue.opacity(0.05))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(
                            isRec ? Color.red.opacity(0.5) : Color.blue.opacity(0.2)
                        ))
                }
                .buttonStyle(.plain)
                
                // 清除当前录入按钮
                if val != nil || isRec {
                    Button(action: { val = nil; isRec = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// ============ 录制逻辑（已修复）============
// 录制逻辑（修复 Optional 错误）
struct KeyLogic: NSViewRepresentable {
    @Binding var r1: Bool
    @Binding var r2: Bool
    @Binding var t1: (UInt16, UInt64)?
    @Binding var t2: (UInt16, UInt64)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(r1: $r1, r2: $r2, t1: $t1, t2: $t2)
    }
    
    func makeNSView(context: Context) -> NSView {
        let kv = KV(coordinator: context.coordinator)
        return kv
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    class Coordinator: NSObject {
        @Binding var r1: Bool
        @Binding var r2: Bool
        @Binding var t1: (UInt16, UInt64)?
        @Binding var t2: (UInt16, UInt64)?
        
        init(r1: Binding<Bool>, r2: Binding<Bool>, t1: Binding<(UInt16, UInt64)?>, t2: Binding<(UInt16, UInt64)?>) {
            _r1 = r1
            _r2 = r2
            _t1 = t1
            _t2 = t2
        }
    }
}

// NSView 子类（修复 coordinator 类型）
class KV: NSView {
    var coordinator: KeyLogic.Coordinator  // ✅ 改为非 Optional
    
    override var acceptsFirstResponder: Bool { true }
    
    init(coordinator: KeyLogic.Coordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseDown(with event: NSEvent) {
        self.window?.makeFirstResponder(self)
    }
    
    override func keyDown(with e: NSEvent) {
        // ✅ 直接访问，不要用 guard let
        if coordinator.r1 == true || coordinator.r2 == true {
            let code = UInt16(e.keyCode)
            let flags = UInt64(e.modifierFlags.rawValue)
            
            if coordinator.r1 == true {
                coordinator.t1 = (code, flags)
                coordinator.r1 = false
            } else if coordinator.r2 == true {
                coordinator.t2 = (code, flags)
                coordinator.r2 = false
            }
            return
        }
        super.keyDown(with: e)
    }
}

// ============ 设置页面 ============
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("setting_launch_at_login") private var launchAtLogin = false
    @AppStorage("setting_hide_dock") private var hideDock = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("设置")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 15) {
                // 开机启动
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("开机自动启动")
                            .font(.system(size: 13, weight: .medium))
                        Text("登录时自动运行此应用")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { newValue in
                            toggleLaunchAtLogin(enabled: newValue)
                        }
                }
                
                Divider()
                
                // 隐藏程序坞
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("隐藏程序坞图标")
                            .font(.system(size: 13, weight: .medium))
                        Text("应用将在后台运行")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $hideDock)
                        .toggleStyle(.switch)
                        .onChange(of: hideDock) { newValue in
                            toggleDockIcon(hide: newValue)
                        }
                }
                
                Divider()
                
                // 菜单栏图标
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("显示菜单栏图标")
                            .font(.system(size: 13, weight: .medium))
                        Text("在菜单栏显示小箭头图标")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $showMenuBarIcon)
                        .toggleStyle(.switch)
                        .onChange(of: showMenuBarIcon) { newValue in
                            updateMenuBarIconVisibility(visible: newValue)
                        }
                }
            }
            .padding(.horizontal, 5)
            
            Spacer()
        }
        .padding(20)
        .frame(width: 300, height: 320)
    }
    
    // 开机启动（传统 LaunchAgents 方式）
    private func toggleLaunchAtLogin(enabled: Bool) {
        let service = SMAppService.mainApp // 2. 使用系统标准服务
        
        if enabled {
            do {
                try service.register() // 3. 注册开机启动
                print("Successfully registered launch service")
            } catch {
                print("Failed to register: \(error.localizedDescription)")
                // 如果注册失败，把开关拨回去
                DispatchQueue.main.async {
                    self.launchAtLogin = false
                }
            }
        } else {
            service.unregister { error in // 4. 取消注册
                if let error = error {
                    print("Failed to unregister: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // 隐藏程序坞
    private func toggleDockIcon(hide: Bool) {
        let policy: NSApplication.ActivationPolicy = hide ? .accessory : .regular
        NSApplication.shared.setActivationPolicy(policy)
        
    }
    
    // 菜单栏图标控制
    private func updateMenuBarIconVisibility(visible: Bool) {
        if visible {
            setupMenuBarIcon()
            alertMessage("菜单栏图标已显示", "你可以从右上角点击图标打开应用")
        } else {
            removeMenuBarIcon()
            alertMessage("菜单栏图标已隐藏", "请通过 Spotlight 打开应用")
        }
    }
    
    // 创建菜单栏图标
    private func setupMenuBarIcon() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = createArrowIcon()
            button.title = "KeyMapper"
            button.action = #selector(AppDelegate.toggleWindow)
            button.target = AppDelegate.self
            
            // 创建菜单
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "显示窗口", action: #selector(AppDelegate.toggleWindow), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "退出 KeyMapper", action: #selector(AppDelegate.quitApp), keyEquivalent: "q"))
            statusItem.menu = menu
            
            UserDefaults.standard.set(true, forKey: "hasMenuBarIcon")
        }
    }
    
    // 移除菜单栏图标
    private func removeMenuBarIcon() {
        NSStatusBar.system.removeStatusItem(NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength))
        UserDefaults.standard.set(false, forKey: "hasMenuBarIcon")
    }
    
    // 创建箭头图标
    private func createArrowIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 3, y: 10))
        path.line(to: NSPoint(x: 9, y: 4))
        path.line(to: NSPoint(x: 15, y: 10))
        
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.black.setStroke()
        path.stroke()
        
        image.unlockFocus()
        image.isTemplate = true
        
        return image
    }
    
    // 显示提示弹窗
    private func alertMessage(_ title: String, _ message: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好的")
            alert.runModal()
        }
    }
}

// ============ 提示条组件 ============
struct AlertBanner: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundColor(.yellow)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(Color.yellow.opacity(0.2))
            .cornerRadius(5)
    }
}

// ============ 应用代理类 ============
class AppDelegate: NSObject, NSApplicationDelegate {
    static let instance = AppDelegate()
    
    @objc static func toggleWindow() {
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
    
    @objc static func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
