import SwiftUI

// MARK: - RulesView
// 映射规则管理页面。
// 上方展示所有映射规则列表（源键 → 目标键 + 备注 + 启用开关 + 删除按钮），
// 下方提供新增映射的录入区：支持录制模式和选择模式两种输入方式。

struct RulesView: View {
    @StateObject var engine = MyEngine.shared
    @State private var tmpTrig: (UInt16, UInt64)?
    @State private var tmpTarg: (UInt16, UInt64)?
    @State private var tmpNote: String = ""
    @State private var isRec1 = false
    @State private var isRec2 = false
    @State private var editingNoteId: UUID? = nil
    @State private var editingNoteText: String = ""
    // 按键选择器弹出状态
    @State private var showSourceKeyPicker = false
    @State private var showTargetKeyPicker = false
    // 编辑已有规则的按键
    @State private var editingRuleId: UUID? = nil
    @State private var editingKeyType: KeyType = .source
    @State private var showEditKeyPicker = false
    @State private var editSelection: (UInt16, UInt64)? = nil

    enum KeyType {
        case source
        case target
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(NSLocalizedString("rules.title", comment: ""))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // 规则列表
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text(NSLocalizedString("rules.original.key", comment: ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text(NSLocalizedString("rules.map.to", comment: ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text(NSLocalizedString("rules.note", comment: ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text(NSLocalizedString("rules.enable", comment: ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .center)

                        Text(NSLocalizedString("rules.actions", comment: ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .center)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    Divider()
                        .padding(.horizontal, 20)

                    ForEach(Array(engine.list.enumerated()), id: \.element.id) { index, m in
                        HStack(spacing: 0) {
                            // 源按键显示与修改按钮
                            HStack(spacing: 4) {
                                Text(MyMap.getName(m.fCode, m.fFlags))
                                    .font(.system(size: 13, weight: .medium))
                                Button(action: {
                                    editSelection = (m.fCode, m.fFlags)
                                    editingRuleId = m.id
                                    editingKeyType = .source
                                    showEditKeyPicker = true
                                }) {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(NSLocalizedString("rules.edit.key", comment: ""))
                            }
                            .frame(maxWidth: .infinity, alignment: .center)

                            // 目标按键显示与修改按钮
                            HStack(spacing: 4) {
                                Text(MyMap.getName(m.tCode, m.tFlags))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.accentColor)
                                Button(action: {
                                    editSelection = (m.tCode, m.tFlags)
                                    editingRuleId = m.id
                                    editingKeyType = .target
                                    showEditKeyPicker = true
                                }) {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(NSLocalizedString("rules.edit.key", comment: ""))
                            }
                            .frame(maxWidth: .infinity, alignment: .center)

                            if editingNoteId == m.id {
                                TextField(NSLocalizedString("rules.note.placeholder", comment: ""), text: $editingNoteText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(4)
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(4)
                                    .onSubmit {
                                        saveNote(for: m.id)
                                    }
                                    .onExitCommand {
                                        editingNoteId = nil
                                    }
                            } else {
                                Text(m.note.isEmpty ? "-" : m.note)
                                    .font(.system(size: 12))
                                    .foregroundColor(m.note.isEmpty ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .onTapGesture {
                                        editingNoteId = m.id
                                        editingNoteText = m.note
                                    }
                            }

                            Toggle("", isOn: Binding(
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
                            .frame(width: 60, alignment: .center)

                            Button(action: { engine.list.removeAll { $0.id == m.id } }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 50, alignment: .center)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(index % 2 == 1 ? Color.gray.opacity(0.1) : Color.clear)
                        .contentShape(Rectangle())
                        .onHover { isHovered in
                            if isHovered {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }

                    Color.clear
                        .frame(height: 20)
                }
            }

            Divider()

            // 新增映射录入区
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    // 源按键输入区：录制框 + 选择器按钮
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("rules.press.original", comment: ""))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 4) {
                            RecordBox(isRec: $isRec1, val: $tmpTrig) {
                                if isRec1 { isRec2 = false }
                            }

                            // 按键选择器按钮：点击弹出可视化按键选择面板
                            Button(action: {
                                isRec1 = false
                                isRec2 = false
                                showSourceKeyPicker = true
                            }) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, height: 24)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color(NSColor.controlBackgroundColor))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(NSLocalizedString("rules.pick.key", comment: ""))
                            .popover(isPresented: $showSourceKeyPicker) {
                                KeyPickerView(selection: $tmpTrig, onDismiss: {
                                    showSourceKeyPicker = false
                                }, onConfirm: {
                                    showSourceKeyPicker = false
                                })
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(.top, 16)

                    // 目标按键输入区：录制框 + 选择器按钮
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("rules.map.as", comment: ""))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 4) {
                            RecordBox(isRec: $isRec2, val: $tmpTarg) {
                                if isRec2 { isRec1 = false }
                            }

                            Button(action: {
                                isRec1 = false
                                isRec2 = false
                                showTargetKeyPicker = true
                            }) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, height: 24)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color(NSColor.controlBackgroundColor))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(NSLocalizedString("rules.pick.key", comment: ""))
                            .popover(isPresented: $showTargetKeyPicker) {
                                KeyPickerView(selection: $tmpTarg, onDismiss: {
                                    showTargetKeyPicker = false
                                }, onConfirm: {
                                    showTargetKeyPicker = false
                                })
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("rules.note", comment: ""))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        TextField(NSLocalizedString("rules.note.placeholder", comment: ""), text: $tmpNote)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                }

                Button(action: addMapping) {
                    Text(NSLocalizedString("rules.save", comment: ""))
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(tmpTrig == nil || tmpTarg == nil)
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .background(KeyLogic(r1: $isRec1, r2: $isRec2, t1: $tmpTrig, t2: $tmpTarg))
        .onChange(of: isRec1) { _ in engine.isRecording = isRec1 || isRec2 }
        .onChange(of: isRec2) { _ in engine.isRecording = isRec1 || isRec2 }
        // 打开选择器时退出录制模式
        .onChange(of: showSourceKeyPicker) { showing in
            if showing { isRec1 = false; isRec2 = false }
        }
        .onChange(of: showTargetKeyPicker) { showing in
            if showing { isRec1 = false; isRec2 = false }
        }
        // 打开编辑选择器时退出录制模式
        .onChange(of: showEditKeyPicker) { showing in
            if showing { isRec1 = false; isRec2 = false }
        }
        // 编辑选择器 popover
        .overlay {
            if showEditKeyPicker {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showEditKeyPicker = false
                        editSelection = nil
                    }
                    .overlay(alignment: .center) {
                        KeyPickerView(selection: $editSelection, onDismiss: {
                            showEditKeyPicker = false
                        }, onConfirm: {
                            applyKeyEdit()
                            showEditKeyPicker = false
                        })
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(NSColor.windowBackgroundColor))
                                .shadow(radius: 10)
                        )
                    }
            }
        }
    }

    func applyKeyEdit() {
        guard let ruleId = editingRuleId, let newKey = editSelection else { return }
        if let idx = engine.list.firstIndex(where: { $0.id == ruleId }) {
            switch editingKeyType {
            case .source:
                engine.list[idx].fCode = newKey.0
                engine.list[idx].fFlags = newKey.1
            case .target:
                engine.list[idx].tCode = newKey.0
                engine.list[idx].tFlags = newKey.1
            }
        }
        editingRuleId = nil
        editSelection = nil
    }

    func addMapping() {
        if let a = tmpTrig, let b = tmpTarg {
            engine.list.append(MyMap(fCode: a.0, fFlags: a.1, tCode: b.0, tFlags: b.1, note: tmpNote))
            tmpTrig = nil
            tmpTarg = nil
            tmpNote = ""
        }
    }

    func saveNote(for id: UUID) {
        if let idx = engine.list.firstIndex(where: { $0.id == id }) {
            engine.list[idx].note = editingNoteText
        }
        editingNoteId = nil
    }
}

// MARK: - RecordBox
// 按键录制交互组件。
// 三种状态：
// - 录制中：显示进度指示器和"录制中"文字
// - 已录制：显示捕获的按键名称
// - 未录制：显示"点击录制"提示

struct RecordBox: View {
    @Binding var isRec: Bool
    @Binding var val: (UInt16, UInt64)?
    var onToggle: () -> Void

    var body: some View {
        HStack {
            if isRec {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text(NSLocalizedString("rules.recording", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
            } else if let v = val {
                Text(MyMap.getName(v.0, v.1))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)
            } else {
                Text(NSLocalizedString("rules.click.record", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isRec ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 2])
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isRec ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            isRec.toggle()
            onToggle()
        }
    }
}
