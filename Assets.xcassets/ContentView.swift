import SwiftUI
import Combine

// 1. 模型部分：保持不变
struct MyMap: Identifiable, Codable {
    var id = UUID()
    var fCode: UInt16
    var fFlags: UInt64
    var tCode: UInt16
    var tFlags: UInt64
    var isOn: Bool = true
    
    static func getName(_ c: UInt16, _ f: UInt64) -> String {
        var s = ""
        // 修饰键
        if (f & 0x40000) != 0 { s += "⌃" }
        if (f & 0x80000) != 0 { s += "⌥" }
        if (f & 0x20000) != 0 { s += "⇧" }
        if (f & 0x100000) != 0 { s += "⌘" }
        
        // 手动对照表：KeyCode -> 人类语言
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 31: "I", 32: "U", 33: "[", 34: "O", 35: "P", 37: "L", 38: "J",
            39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            49: "Space", 36: "↩", 51: "⌫", 53: "Esc", 48: "Tab",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        
        return s + (keyMap[c] ?? "K\(c)")
    }
}

// 2. 引擎部分：保持之前的“自动重连版”逻辑
class MyEngine: ObservableObject {
    static let shared = MyEngine()
    @Published var list: [MyMap] = [] { didSet { save() } }
    @Published var isActive: Bool = false
    private var tap: CFMachPort?
    private var retryTimer: Timer?
    
    init() { load(); start() }
    func save() { if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: "saved_maps") } }
    func load() { if let data = UserDefaults.standard.data(forKey: "saved_maps"), let decoded = try? JSONDecoder().decode([MyMap].self, from: data) { self.list = decoded } }

    func start() {
        retryTimer?.invalidate()
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { (proxy, type, event, _) -> Unmanaged<CGEvent>? in
            let c = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let f = event.flags.rawValue
            if event.getIntegerValueField(.eventSourceUserData) == 12345 { return Unmanaged.passRetained(event) }
            let modifierMask: UInt64 = 0x40000 | 0x80000 | 0x20000 | 0x100000
            let currentModifiers = f & modifierMask
            if let m = MyEngine.shared.list.first(where: { $0.isOn && $0.fCode == c && ($0.fFlags & modifierMask) == currentModifiers }) {
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
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: nil)
        if let t = tap {
            let s = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
            CGEvent.tapEnable(tap: t, enable: true)
            self.isActive = true
        } else {
            self.isActive = false
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.start() }
        }
    }
}

// 3. 优化后的 UI：增加删除和重置功能
struct ContentView: View {
    @StateObject var engine = MyEngine.shared
    @State private var tmpTrig: (UInt16, UInt64)?
    @State private var tmpTarg: (UInt16, UInt64)?
    @State private var isRec1 = false
    @State private var isRec2 = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 授权状态条
            HStack {
                Circle().fill(engine.isActive ? Color.green : Color.red).frame(width: 8, height: 8)
                Text(engine.isActive ? "引擎运行中" : "等待授权...").font(.system(size: 11, weight: .medium)).foregroundColor(engine.isActive ? .green : .red)
                Spacer()
                if !engine.isActive {
                    Button("去开启") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }.buttonStyle(.link).font(.caption)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(engine.isActive ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
            
            HStack(alignment: .top, spacing: 0) {
                // 左侧：新建映射区
                VStack(spacing: 15) {
                    Text("新建映射").font(.headline)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        RecordRow(isRec: $isRec1, val: $tmpTrig, title: "按下原键:") { if isRec1 { isRec2 = false } }
                        RecordRow(isRec: $isRec2, val: $tmpTarg, title: "映射为:") { if isRec2 { isRec1 = false } }
                    }
                    .padding(10)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(8)
                    
                    Button(action: addMapping) {
                        Label("保存规则", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(tmpTrig == nil || tmpTarg == nil)
                }
                .padding().frame(width: 200)
                
                Divider()
                
                // 右侧：规则列表区
                VStack(alignment: .leading, spacing: 0) {
                    Text("已保存规则").font(.system(size: 11, weight: .bold)).foregroundColor(.secondary).padding([.leading, .top], 10)
                    List {
                        ForEach(engine.list) { m in
                            HStack(spacing: 8) {
                                Text(MyMap.getName(m.fCode, m.fFlags)).font(.system(size: 12, design: .monospaced)).frame(width: 50, alignment: .leading)
                                Image(systemName: "arrow.right").font(.caption2).foregroundColor(.secondary)
                                Text(MyMap.getName(m.tCode, m.tFlags)).font(.system(size: 12, design: .monospaced)).foregroundColor(.blue).frame(width: 50, alignment: .leading)
                                
                                Spacer()
                                
                                // 显式删除按钮
                                Button(action: { deleteById(m.id) }) {
                                    Image(systemName: "trash").font(.caption).foregroundColor(.red.opacity(0.7))
                                }.buttonStyle(.plain)
                                
                                Toggle("", isOn: Binding(
                                    get: { m.isOn },
                                    set: { val in if let idx = engine.list.firstIndex(where: { $0.id == m.id }) { engine.list[idx].isOn = val } }
                                )).toggleStyle(.switch).scaleEffect(0.7).labelsHidden()
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
    }
    
    func addMapping() {
        if let a = tmpTrig, let b = tmpTarg {
            engine.list.append(MyMap(fCode: a.0, fFlags: a.1, tCode: b.0, tFlags: b.1))
            tmpTrig = nil; tmpTarg = nil
        }
    }
    
    func deleteById(_ id: UUID) {
        engine.list.removeAll { $0.id == id }
    }
}

// 4. 辅助组件：带“清除”功能的录制行
struct RecordRow: View {
    @Binding var isRec: Bool
    @Binding var val: (UInt16, UInt64)?
    let title: String
    var onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundColor(.secondary)
            HStack(spacing: 6) {
                Button(action: { isRec.toggle(); onToggle() }) {
                    Text(isRec ? "等待输入..." : (val == nil ? "点击录制" : MyMap.getName(val!.0, val!.1)))
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(isRec ? Color.red.opacity(0.1) : Color.blue.opacity(0.05))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(isRec ? Color.red.opacity(0.5) : Color.blue.opacity(0.2)))
                }.buttonStyle(.plain)
                
                // --- 新增：清除当前录入按钮 ---
                if val != nil || isRec {
                    Button(action: { val = nil; isRec = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

// 录制逻辑保持不变
struct KeyLogic: NSViewRepresentable {
    @Binding var r1: Bool; @Binding var r2: Bool
    @Binding var t1: (UInt16, UInt64)?; @Binding var t2: (UInt16, UInt64)?
    class KV: NSView {
        var p: KeyLogic?
        override var acceptsFirstResponder: Bool { true }
        override func mouseDown(with event: NSEvent) { self.window?.makeFirstResponder(self) }
        override func keyDown(with e: NSEvent) {
            if p?.r1 == true || p?.r2 == true {
                let code = UInt16(e.keyCode); let flags = UInt64(e.modifierFlags.rawValue)
                if p?.r1 == true { p?.t1 = (code, flags); p?.r1 = false }
                else if p?.r2 == true { p?.t2 = (code, flags); p?.r2 = false }
                return
            }
            super.keyDown(with: e)
        }
    }
    func makeNSView(context: Context) -> NSView { let v = KV(); v.p = self; return v }
    func updateNSView(_ nsView: NSView, context: Context) {
        if r1 || r2 { DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) } }
    }
}
