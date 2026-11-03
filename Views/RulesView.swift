import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - RulesView
// 映射规则管理页面。
// 上方展示映射规则摘要与可展开的编辑详情，
// 下方提供新增映射的录入区：支持录制模式和选择模式两种输入方式。

struct RulesView: View {
    @StateObject var engine = MyEngine.shared
    @AppStorage("rules_sort_order") private var sortOrder: RuleSortOrder = .newestFirst
    @State private var tmpTrig: (UInt16, UInt64)?
    @State private var tmpTarg: (UInt16, UInt64)?
    @State private var tmpTrigSides: ModifierSideSelection = .any
    @State private var tmpTargSides: ModifierSideSelection = .any
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
    @State private var editSelectionSides: ModifierSideSelection = .any
    @State private var runningApps: [RunningAppInfo] = []

    private var allRules: [MyMap] {
        engine.list + engine.modifierMappings.map(\.rule)
    }

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
                    Picker(NSLocalizedString("rules.sort", comment: ""), selection: $sortOrder) {
                        ForEach(RuleSortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Label(NSLocalizedString("rules.sort", comment: ""), systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // 按可用宽度增加列数，窄窗口保留单列；每张卡片至少预留 380pt。
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 380), spacing: 14, alignment: .top)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(sortOrder.sorted(allRules)) { m in
                        RuleItemRow(
                            mapping: m,
                            isEditingNote: editingNoteId == m.id,
                            editingNoteText: $editingNoteText,
                            isEnabled: Binding(
                                get: { m.isOn },
                                set: { val in
                                    updateRule(m.id) { $0.isOn = val }
                                }
                            ),
                            onEditSource: {
                                editSelection = (m.fCode, m.fFlags)
                                editSelectionSides = m.fModifierSides
                                editingRuleId = m.id
                                editingKeyType = .source
                                showEditKeyPicker = true
                            },
                            onEditTarget: {
                                editSelection = (m.tCode, m.tFlags)
                                editSelectionSides = m.tModifierSides
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
                            onDismissUsageHint: {
                                updateRule(m.id) { $0.hasDismissedUsageHint = true }
                            },
                            onDelete: {
                                engine.list.removeAll { $0.id == m.id }
                                engine.modifierMappings.removeAll { $0.id == m.id }
                            },
                            runningApps: runningApps,
                            appFilterMode: Binding(
                                get: { m.appFilterMode },
                                set: { mode in updateRule(m.id) { $0.appFilterMode = mode } }
                            ),
                            onAddRunningAppFilter: { bundleId, list in
                                addAppFilter(bundleId, list: list, to: m.id)
                            },
                            onAddAppFilterFromFinder: { list in
                                addAppFilterFromFinder(list: list, to: m.id)
                            },
                            onRemoveAppFilter: { bundleId, list in
                                removeAppFilter(bundleId, list: list, from: m.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .modifier(RulesScrollHeight(ruleIDs: allRules.map(\.id), sortOrder: sortOrder))
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
                            RecordBox(isRec: $isRec1, val: $tmpTrig, modifierSides: tmpTrigSides) {
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
                                KeyPickerView(selection: $tmpTrig, modifierSides: $tmpTrigSides, allowsModifierOnly: true, onDismiss: {
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
                            RecordBox(isRec: $isRec2, val: $tmpTarg, modifierSides: tmpTargSides) {
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
                                KeyPickerView(selection: $tmpTarg, modifierSides: $tmpTargSides, allowsModifierOnly: true, onDismiss: {
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
                .disabled(tmpTrig == nil || tmpTarg == nil || isRec1 || isRec2)

            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .background(KeyLogic(r1: $isRec1, r2: $isRec2, t1: $tmpTrig, t2: $tmpTarg, s1: $tmpTrigSides, s2: $tmpTargSides, allowsModifierOnly: true))
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
                        KeyPickerView(selection: $editSelection, modifierSides: $editSelectionSides, allowsModifierOnly: true, onDismiss: {
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
        .onDisappear {
            cancelKeyRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cancelKeyRecording)) { _ in
            cancelKeyRecording()
        }
    }

    private func cancelKeyRecording() {
        isRec1 = false
        isRec2 = false
        engine.isRecording = false
    }

    func applyKeyEdit() {
        guard let ruleId = editingRuleId, let newKey = editSelection else { return }
        updateRule(ruleId) { rule in
            switch editingKeyType {
            case .source:
                rule.fCode = newKey.0
                rule.fFlags = newKey.1
                rule.fModifierSides = editSelectionSides
            case .target:
                rule.tCode = newKey.0
                rule.tFlags = newKey.1
                rule.tModifierSides = editSelectionSides
            }
        }
        editingRuleId = nil
        editSelection = nil
        editSelectionSides = .any
    }

    func addMapping() {
        guard !isRec1, !isRec2, let a = tmpTrig, let b = tmpTarg else { return }

        engine.list.append(MyMap(
            fCode: a.0, fFlags: a.1, tCode: b.0, tFlags: b.1,
            fModifierSides: tmpTrigSides, tModifierSides: tmpTargSides, note: tmpNote
        ))
        tmpTrig = nil
        tmpTarg = nil
        tmpTrigSides = .any
        tmpTargSides = .any
        tmpNote = ""
        cancelKeyRecording()
    }

    private func updateRule(_ id: UUID, change: (inout MyMap) -> Void) {
        guard let original = allRules.first(where: { $0.id == id }) else { return }
        var rule = original
        change(&rule)
        if rule.fCode != original.fCode || rule.fFlags != original.fFlags
            || rule.tCode != original.tCode || rule.tFlags != original.tFlags
            || rule.fModifierSides != original.fModifierSides || rule.tModifierSides != original.tModifierSides {
            rule.hasDismissedUsageHint = false
        }
        if let index = engine.list.firstIndex(where: { $0.id == id }) {
            engine.list[index] = rule
        } else if engine.modifierMappings.contains(where: { $0.id == id }) {
            // 兼容此前保存的独立修饰键规则，编辑后统一使用普通规则模型。
            engine.modifierMappings.removeAll { $0.id == id }
            engine.list.append(rule)
        }
    }

    func saveNote(for id: UUID) {
        updateRule(id) { $0.note = editingNoteText }
        editingNoteId = nil
    }

    func addAppFilter(_ bundleId: String, list: AppFilterMode, to id: UUID) {
        updateRule(id) {
            $0.appFilterMode = list
            if !$0[appList: list].contains(bundleId) { $0[appList: list].append(bundleId) }
        }
    }

    func addAppFilterFromFinder(list: AppFilterMode, to id: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = NSLocalizedString("app.filter.select", comment: "")

        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier else { return }

        addAppFilter(bundleId, list: list, to: id)
    }

    func removeAppFilter(_ bundleId: String, list: AppFilterMode, from id: UUID) {
        updateRule(id) { $0[appList: list].removeAll { $0 == bundleId } }
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

// 保留当前宽度下出现过的最大内容高度。收起卡片时，减少的高度转为底部留白，
// 防止滚动到列表末尾后因内容变短而被 ScrollView 强制上移。
private struct RulesScrollHeight: ViewModifier {
    let ruleIDs: [UUID]
    let sortOrder: RuleSortOrder
    @State private var retainedSize: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { geometry in
                geometry.size
            } action: { size in
                guard size.width > 0 else { return }
                if size.width != retainedSize.width {
                    // 换宽度的首轮高度可能仍含 LazyVGrid 的旧行高估算，先清空留白。
                    retainedSize = CGSize(width: size.width, height: 0)
                } else if size.height > retainedSize.height {
                    retainedSize.height = size.height
                }
            }
            .frame(minHeight: retainedSize.height, alignment: .top)
            .onChange(of: ruleIDs) { _ in retainedSize = .zero }
            .onChange(of: sortOrder) { _ in retainedSize = .zero }
    }
}

struct RunningAppInfo: Identifiable {
    let bundleId: String
    let name: String

    var id: String { bundleId }
}

// MARK: - RuleItemRow
// 默认展示规则摘要，点击卡片展开按键、备注和应用黑名单编辑。

private enum RuleCardTypography {
    static let bodySize: CGFloat = 12
    static let key = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: bodySize)
    static let label = Font.system(size: bodySize, weight: .medium)
}

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
    let onDismissUsageHint: () -> Void
    let onDelete: () -> Void
    let runningApps: [RunningAppInfo]
    @Binding var appFilterMode: AppFilterMode
    let onAddRunningAppFilter: (String, AppFilterMode) -> Void
    let onAddAppFilterFromFinder: (AppFilterMode) -> Void
    let onRemoveAppFilter: (String, AppFilterMode) -> Void

    @State private var isExpanded = false
    @State private var isHovered = false

    private var sourceName: String {
        MyMap.getName(mapping.fCode, mapping.fFlags, mapping.fModifierSides)
    }

    private var targetName: String {
        MyMap.getName(mapping.tCode, mapping.tFlags, mapping.tModifierSides)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    alignedColumns(showsArrow: true) {
                        Button(action: onEditSource) {
                            shortcutLabel(sourceName, isTarget: false)
                        }
                        .buttonStyle(.plain)
                    } target: {
                        Button(action: onEditTarget) {
                            shortcutLabel(targetName, isTarget: true)
                        }
                        .buttonStyle(.plain)
                    }

                    alignedColumns(showsArrow: false) {
                        Text(mapping.note)
                            .font(RuleCardTypography.body)
                            .lineLimit(1)
                    } target: {
                        if mapping.appFilterMode == .whitelist || !mapping.appBlacklist.isEmpty {
                            Text(appFilterSummary)
                                .font(RuleCardTypography.body)
                                .lineLimit(1)
                        } else if mapping.showsUsageHint {
                            Label(NSLocalizedString("rules.usage.tip", comment: ""), systemImage: "info.circle")
                                .font(RuleCardTypography.body)
                                .lineLimit(1)
                                .help(NSLocalizedString("modifiers.usage.hint", comment: ""))
                        } else {
                            Color.clear
                        }
                    }
                    .foregroundColor(.secondary)
                    .frame(height: 16)
                }
                .opacity(isEnabled ? 1 : 0.45)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Toggle(NSLocalizedString("rules.enable", comment: ""), isOn: $isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .frame(width: 36, height: 28)

                    Button(action: toggleDetails) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.primary.opacity(isExpanded || isHovered ? 0.06 : 0))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(NSLocalizedString(isExpanded ? "rules.details.collapse" : "rules.details.expand", comment: ""))
                    .accessibilityLabel(NSLocalizedString(isExpanded ? "rules.details.collapse" : "rules.details.expand", comment: ""))
                }
                .frame(width: 68, height: 28)
            }

            if isExpanded {
                ruleDetails
            }

            if isExpanded && mapping.showsUsageHint {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                    Text(NSLocalizedString("modifiers.usage.hint", comment: ""))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(action: onDismissUsageHint) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(NSLocalizedString("modifiers.usage.dismiss", comment: ""))
                }
                .font(RuleCardTypography.body)
                .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isExpanded ? Color.accentColor.opacity(0.3) : Color.primary.opacity(isHovered ? 0.16 : 0.08),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: toggleDetails)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(action: toggleDetails) {
                Label(NSLocalizedString(isExpanded ? "rules.details.collapse" : "rules.edit", comment: ""), systemImage: "slider.horizontal.3")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label(NSLocalizedString("rules.delete", comment: ""), systemImage: "trash")
            }
        }
    }

    // 摘要与辅助信息共用等宽的源键/目标键两列，箭头固定占 16pt。
    // 列宽只由卡片宽度决定，按键名称、备注及黑名单内容不会改变列的位置。
    private func alignedColumns<Source: View, Target: View>(
        showsArrow: Bool,
        @ViewBuilder source: () -> Source,
        @ViewBuilder target: () -> Target
    ) -> some View {
        HStack(spacing: 10) {
            source()
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .opacity(showsArrow ? 1 : 0)
                .frame(width: 16)
            target()
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
    }

    private func shortcutLabel(_ title: String, isTarget: Bool) -> some View {
        Text(title.trimmingCharacters(in: .whitespaces))
            .font(RuleCardTypography.key)
            .foregroundColor(isTarget ? .accentColor : .primary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isTarget ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isTarget ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .help(title)
    }

    private var ruleDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(NSLocalizedString("rules.note", comment: ""))
                        .font(RuleCardTypography.label)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(role: .destructive, action: onDelete) {
                        Label(NSLocalizedString("rules.delete", comment: ""), systemImage: "trash")
                            .font(RuleCardTypography.body)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }

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
                    Button(action: onStartEditingNote) {
                        Text(mapping.note.isEmpty ? NSLocalizedString("rules.note.placeholder", comment: "") : mapping.note)
                            .font(RuleCardTypography.body)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            RuleAppFilterSection(
                mode: $appFilterMode,
                blacklist: mapping.appBlacklist,
                whitelist: mapping.appWhitelist,
                runningApps: runningApps,
                onAddRunningApp: onAddRunningAppFilter,
                onAddFromFinder: onAddAppFilterFromFinder,
                onDelete: onRemoveAppFilter
            )

        }
    }

    private var appFilterSummary: String {
        let isWhitelist = mapping.appFilterMode == .whitelist
        let bundleIDs = mapping[appList: mapping.appFilterMode]
        if isWhitelist && bundleIDs.isEmpty {
            return NSLocalizedString("rules.allowed.none", comment: "")
        }
        return String(format: NSLocalizedString(isWhitelist ? "rules.allowed.count" : "rules.excluded.count", comment: ""), bundleIDs.count)
    }

    private func toggleDetails() {
        if isExpanded && isEditingNote {
            onSaveNote()
        }
        isExpanded.toggle()
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
        textField.font = .systemFont(ofSize: RuleCardTypography.bodySize)
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

private enum RuleAppListLayout {
    static let inset: CGFloat = 0
    static let iconSize: CGFloat = 20
    static let actionSize: CGFloat = 24
    static let spacing: CGFloat = 6
}

struct RuleAppFilterSection: View {
    @Binding var mode: AppFilterMode
    let blacklist: [String]
    let whitelist: [String]
    let runningApps: [RunningAppInfo]
    let onAddRunningApp: (String, AppFilterMode) -> Void
    let onAddFromFinder: (AppFilterMode) -> Void
    let onDelete: (String, AppFilterMode) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Divider()
            Grid(alignment: .topLeading, horizontalSpacing: 22, verticalSpacing: 8) {
                GridRow {
                    listHeader(.blacklist, bundleIDs: blacklist)
                    listHeader(.whitelist, bundleIDs: whitelist)
                }
                GridRow {
                    listDescription(.blacklist, bundleIDs: blacklist)
                    listDescription(.whitelist, bundleIDs: whitelist)
                }
                if !blacklist.isEmpty || !whitelist.isEmpty {
                    GridRow {
                        appItems(.blacklist, bundleIDs: blacklist)
                        appItems(.whitelist, bundleIDs: whitelist)
                    }
                }
            }
            .overlay {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private func listHeader(_ list: AppFilterMode, bundleIDs: [String]) -> some View {
        HStack(spacing: RuleAppListLayout.spacing) {
            Button {
                mode = list
            } label: {
                HStack(spacing: RuleAppListLayout.spacing) {
                    Image(systemName: mode == list ? "largecircle.fill.circle" : "circle")
                        .frame(width: RuleAppListLayout.iconSize, height: RuleAppListLayout.actionSize)
                    Text(NSLocalizedString(list == .blacklist ? "rules.list.blacklist" : "rules.list.whitelist", comment: ""))
                }
                .font(RuleCardTypography.label)
                .foregroundColor(mode == list ? .accentColor : .secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(mode == list ? .isSelected : [])
            Spacer(minLength: 4)
            Menu {
                ForEach(runningApps) { app in
                    Button {
                        onAddRunningApp(app.bundleId, list)
                    } label: {
                        Label(app.name, systemImage: bundleIDs.contains(app.bundleId) ? "checkmark" : "app")
                    }
                    .disabled(bundleIDs.contains(app.bundleId))
                }
                if runningApps.isEmpty {
                    Text(NSLocalizedString("app.blacklist.no.running.apps", comment: ""))
                }
                Divider()
                Button {
                    onAddFromFinder(list)
                } label: {
                    Label(NSLocalizedString("app.blacklist.add.finder", comment: ""), systemImage: "folder")
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(RuleCardTypography.key)
                    .frame(width: RuleAppListLayout.actionSize, height: RuleAppListLayout.actionSize)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: RuleAppListLayout.actionSize, height: RuleAppListLayout.actionSize)
            .help(NSLocalizedString(list == .blacklist ? "rules.list.blacklist.add" : "rules.list.whitelist.add", comment: ""))
            .accessibilityLabel(NSLocalizedString(list == .blacklist ? "rules.list.blacklist.add" : "rules.list.whitelist.add", comment: ""))
        }
        .padding(.horizontal, RuleAppListLayout.inset)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func listDescription(_ list: AppFilterMode, bundleIDs: [String]) -> some View {
        Text(NSLocalizedString(mode != list ? "rules.list.inactive" : (list == .blacklist ? "rules.list.blacklist.desc" : (bundleIDs.isEmpty ? "rules.list.whitelist.empty" : "rules.list.whitelist.desc")), comment: ""))
            .font(RuleCardTypography.body)
            .foregroundColor(mode == .whitelist && mode == list && bundleIDs.isEmpty ? .orange : .secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func appItems(_ list: AppFilterMode, bundleIDs: [String]) -> some View {
        VStack(spacing: 4) {
            if bundleIDs.isEmpty {
                Color.clear.frame(height: 0)
            }
            ForEach(bundleIDs, id: \.self) { bundleID in
                RuleAppFilterChip(bundleId: bundleID) {
                    onDelete(bundleID, list)
                }
                .opacity(mode == list ? 1 : 0.55)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
    }
}

struct RuleAppFilterChip: View {
    let bundleId: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: RuleAppListLayout.spacing) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: RuleAppListLayout.iconSize, height: RuleAppListLayout.iconSize)
            } else {
                Image(systemName: "app")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: RuleAppListLayout.iconSize, height: RuleAppListLayout.iconSize)
            }

            Text(appName)
                .font(RuleCardTypography.body)
                .lineLimit(1)
                .help(bundleId)

            Spacer(minLength: 4)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(RuleCardTypography.body)
                    .foregroundColor(.secondary)
                    .frame(width: RuleAppListLayout.actionSize, height: RuleAppListLayout.actionSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, RuleAppListLayout.inset)
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

// MARK: - RecordBox
// 按键录制交互组件。
// 三种状态：
// - 录制中：显示进度指示器和"录制中"文字
// - 已录制：显示捕获的按键名称
// - 未录制：显示"点击录制"提示

struct RecordBox: View {
    @Binding var isRec: Bool
    @Binding var val: (UInt16, UInt64)?
    let modifierSides: ModifierSideSelection
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
                Text(MyMap.getName(v.0, v.1, modifierSides))
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
