import SwiftUI
import AppKit

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
                Text(engine.isActive ? NSLocalizedString("engine.running", comment: "") : NSLocalizedString("engine.waiting", comment: ""))
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
                .help(NSLocalizedString("settings", comment: ""))
                
                // 未授权时显示开启按钮
                if !engine.isActive {
                    Button(NSLocalizedString("enable.accessibility", comment: "")) {
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
                    Text(NSLocalizedString("new.mapping", comment: ""))
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        RecordRow(isRec: $isRec1, val: $tmpTrig, title: NSLocalizedString("press.original.key", comment: "")) {
                            if isRec1 { isRec2 = false }
                        }
                        RecordRow(isRec: $isRec2, val: $tmpTarg, title: NSLocalizedString("map.to", comment: "")) {
                            if isRec2 { isRec1 = false }
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(8)
                    
                    Button(action: addMapping) {
                        Label(NSLocalizedString("save.rule", comment: ""), systemImage: "plus.circle.fill")
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
                    Text(NSLocalizedString("saved.rules", comment: ""))
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