import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    @State private var runningApps: [RunningAppInfo] = []

    enum KeyType {
        case source
        case target
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(NSLocalizedString("rules.title", comment: ""))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Menu {
                    if runningApps.isEmpty {
                        Text(NSLocalizedString("global.blacklist.no.running.apps", comment: ""))
                    } else {
                        ForEach(runningApps) { app in
                            Button(action: {
                                addGlobalBlacklistApp(app.bundleId)
                            }) {
                                Label(app.name, systemImage: engine.blacklist.contains(app.bundleId) ? "checkmark" : "app")
                            }
                        }
                    }

                    Divider()

                    Button(action: addGlobalBlacklistFromFinder) {
                        Label(NSLocalizedString("global.blacklist.add.finder", comment: ""), systemImage: "folder")
                    }
                } label: {
                    Label(NSLocalizedString("global.blacklist.add", comment: ""), systemImage: "plus.circle")
                        .font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .onTapGesture {
                    refreshRunningApps()
                }
            }
            .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // 规则列表
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(engine.list) { m in
                        RuleItemRow(
                            mapping: m,
                            isEditingNote: editingNoteId == m.id,
                            editingNoteText: $editingNoteText,
                            isEnabled: Binding(
                                get: { m.isOn },
                                set: { val in
                                    if let idx = engine.list.firstIndex(where: { $0.id == m.id }) {
                                        engine.list[idx].isOn = val
                                    }
                                }
                            ),
                            onEditSource: {
                                editSelection = (m.fCode, m.fFlags)
                                editingRuleId = m.id
                                editingKeyType = .source
                                showEditKeyPicker = true
                            },
                            onEditTarget: {
                                editSelection = (m.tCode, m.tFlags)
                                editingRuleId = m.id
                                editingKeyType = .target
                                showEditKeyPicker = true
                            },
                            onStartEditingNote: {
                                editingNoteId = m.id
                                editingNoteText = m.note
                            },
                            onSaveNote: {
                                saveNote(for: m.id)
                            },
                            onCancelNote: {
                                editingNoteId = nil
                            },
                            onDelete: {
                                engine.list.removeAll { $0.id == m.id }
                            },
                            runningApps: runningApps,
                            onAddRunningAppBlacklist: { bundleId in
                                addAppBlacklist(bundleId, to: m.id)
                            },
                            onAddAppBlacklistFromFinder: {
                                addAppBlacklistFromFinder(to: m.id)
                            },
                            onRemoveAppBlacklist: { bundleId in
                                removeAppBlacklist(bundleId, from: m.id)
                            }
                        )
                    }

                    Color.clear
                        .frame(height: 20)
                }
                .padding(.horizontal, 20)
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
        .onAppear {
            refreshRunningApps()
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
            engine.list.append(MyMap(fCode: a.0, fFlags: a.1, tCode: b.0, tFlags: b.1, note: tmpNote, appBlacklist: engine.blacklist))
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

    func addAppBlacklist(_ bundleId: String, to id: UUID) {
        guard let idx = engine.list.firstIndex(where: { $0.id == id }),
              !engine.list[idx].appBlacklist.contains(bundleId) else { return }

        engine.list[idx].appBlacklist.append(bundleId)
    }

    func addAppBlacklistFromFinder(to id: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = NSLocalizedString("app.blacklist.select", comment: "")

        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier else { return }

        addAppBlacklist(bundleId, to: id)
    }

    func removeAppBlacklist(_ bundleId: String, from id: UUID) {
        if let idx = engine.list.firstIndex(where: { $0.id == id }) {
            engine.list[idx].appBlacklist.removeAll { $0 == bundleId }
        }
    }

    func addGlobalBlacklistApp(_ bundleId: String) {
        engine.addGlobalBlacklistApp(bundleId)
    }

    func addGlobalBlacklistFromFinder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = NSLocalizedString("global.blacklist.select", comment: "")

        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier else { return }

        addGlobalBlacklistApp(bundleId)
    }

    func refreshRunningApps() {
        let currentBundleId = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        runningApps = NSWorkspace.shared.runningApplications
            .compactMap { app -> RunningAppInfo? in
                guard app.activationPolicy == .regular,
                      let bundleId = app.bundleIdentifier,
                      bundleId != currentBundleId,
                      !seen.contains(bundleId) else { return nil }
                seen.insert(bundleId)
                return RunningAppInfo(bundleId: bundleId, name: app.localizedName ?? bundleId)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct RunningAppInfo: Identifiable {
    let bundleId: String
    let name: String

    var id: String { bundleId }
}

// MARK: - RuleItemRow
// 映射规则卡片行，展示源按键、目标按键、备注、启用开关和删除按钮。

struct RuleItemRow: View {
    let mapping: MyMap
    let isEditingNote: Bool
    @Binding var editingNoteText: String
    @Binding var isEnabled: Bool
    let onEditSource: () -> Void
    let onEditTarget: () -> Void
    let onStartEditingNote: () -> Void
    let onSaveNote: () -> Void
    let onCancelNote: () -> Void
    let onDelete: () -> Void
    let runningApps: [RunningAppInfo]
    let onAddRunningAppBlacklist: (String) -> Void
    let onAddAppBlacklistFromFinder: () -> Void
    let onRemoveAppBlacklist: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        RuleKeyButton(
                            title: MyMap.getName(mapping.fCode, mapping.fFlags),
                            foregroundColor: .primary,
                            action: onEditSource
                        )

                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        RuleKeyButton(
                            title: MyMap.getName(mapping.tCode, mapping.tFlags),
                            foregroundColor: .accentColor,
                            action: onEditTarget
                        )
                    }

                    HStack(spacing: 6) {
                        Text(NSLocalizedString("rules.note", comment: ""))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)

                        if isEditingNote {
                            RuleNoteTextField(
                                text: $editingNoteText,
                                placeholder: NSLocalizedString("rules.note.placeholder", comment: ""),
                                onCommit: onSaveNote,
                                onCancel: onCancelNote
                            )
                            .frame(height: 22)
                            .padding(.horizontal, 6)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(5)
                        } else {
                            Text(noteText)
                                .font(.system(size: 10))
                                .foregroundColor(mapping.note.isEmpty ? .secondary.opacity(0.75) : .secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !isEditingNote {
                            onStartEditingNote()
                        }
                    }
                }

                Spacer(minLength: 12)

                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
                    .labelsHidden()
                    .frame(width: 52, alignment: .center)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
            }

            RuleAppBlacklistSection(
                bundleIds: mapping.appBlacklist,
                runningApps: runningApps,
                onAddRunningApp: onAddRunningAppBlacklist,
                onAddFromFinder: onAddAppBlacklistFromFinder,
                onDelete: onRemoveAppBlacklist
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private var noteText: String {
        mapping.note.isEmpty ? NSLocalizedString("rules.note.placeholder", comment: "") : mapping.note
    }
}

struct RuleNoteTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.placeholderString = placeholder
        textField.font = .systemFont(ofSize: 11)
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.commitFromAction)

        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
            context.coordinator.startMonitoring(textField: textField)
        }

        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self
        if textField.stringValue != text {
            textField.stringValue = text
        }
        textField.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RuleNoteTextField
        private weak var textField: NSTextField?
        private var mouseMonitor: Any?
        private var isFinishing = false

        init(parent: RuleNoteTextField) {
            self.parent = parent
        }

        deinit {
            stopMonitoring()
        }

        func startMonitoring(textField: NSTextField) {
            stopMonitoring()
            self.textField = textField

            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self, let textField = self.textField else { return event }

                if event.window !== textField.window {
                    self.commit()
                    return event
                }

                let point = textField.convert(event.locationInWindow, from: nil)
                if !textField.bounds.contains(point) {
                    self.commit()
                }

                return event
            }
        }

        private func stopMonitoring() {
            if let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
                self.mouseMonitor = nil
            }
        }

        @objc func commitFromAction() {
            commit()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            commit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancel()
                return true
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                commit()
                return true
            }

            return false
        }

        private func commit() {
            guard !isFinishing else { return }
            isFinishing = true
            if let textField {
                parent.text = textField.stringValue
            }
            stopMonitoring()
            parent.onCommit()
        }

        private func cancel() {
            guard !isFinishing else { return }
            isFinishing = true
            stopMonitoring()
            parent.onCancel()
        }
    }
}

struct RuleAppBlacklistSection: View {
    let bundleIds: [String]
    let runningApps: [RunningAppInfo]
    let onAddRunningApp: (String) -> Void
    let onAddFromFinder: () -> Void
    let onDelete: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack(spacing: 8) {
                Text(NSLocalizedString("app.blacklist", comment: ""))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                if bundleIds.isEmpty {
                    Text(NSLocalizedString("app.blacklist.empty", comment: ""))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.75))
                }

                Spacer()

                Menu {
                    if runningApps.isEmpty {
                        Text(NSLocalizedString("app.blacklist.no.running.apps", comment: ""))
                    } else {
                        ForEach(runningApps) { app in
                            Button(action: {
                                onAddRunningApp(app.bundleId)
                            }) {
                                Label(app.name, systemImage: bundleIds.contains(app.bundleId) ? "checkmark" : "app")
                            }
                        }
                    }

                    Divider()

                    Button(action: onAddFromFinder) {
                        Label(NSLocalizedString("app.blacklist.add.finder", comment: ""), systemImage: "folder")
                    }
                } label: {
                    Label(NSLocalizedString("app.blacklist.add", comment: ""), systemImage: "plus.circle")
                        .font(.system(size: 10, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .foregroundColor(.accentColor)
            }

            if !bundleIds.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(bundleIds, id: \.self) { bundleId in
                        RuleAppBlacklistChip(bundleId: bundleId) {
                            onDelete(bundleId)
                        }
                    }
                }
            }
        }
    }
}

struct RuleAppBlacklistChip: View {
    let bundleId: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(appName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(bundleId)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(NSColor.textBackgroundColor).opacity(0.7))
        .cornerRadius(6)
    }

    private var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    }

    private var appName: String {
        guard let appURL,
              let bundle = Bundle(url: appURL) else { return bundleId }
        return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundleId
    }

    private var appIcon: NSImage? {
        guard let appURL else { return nil }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}

struct RuleKeyButton: View {
    let title: String
    let foregroundColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(foregroundColor)
        }
        .buttonStyle(.plain)
        .help(NSLocalizedString("rules.edit.key", comment: ""))
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
