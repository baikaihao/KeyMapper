import SwiftUI

// MARK: - KeyGridItem
// 按键网格项，表示一个可选择的按键。
// id 为 macOS 虚拟键码，name 为显示名称。

struct KeyGridItem: Identifiable {
    let id: UInt16
    let name: String

    // 按 QWERTY 键盘布局组织的按键网格数据
    static let organizedRows: [[KeyGridItem]] = [
        // 字母键 - 第一行 (QWERTYUIOP)
        [
            KeyGridItem(id: 12, name: "Q"), KeyGridItem(id: 13, name: "W"),
            KeyGridItem(id: 14, name: "E"), KeyGridItem(id: 15, name: "R"),
            KeyGridItem(id: 17, name: "T"), KeyGridItem(id: 16, name: "Y"),
            KeyGridItem(id: 32, name: "U"), KeyGridItem(id: 34, name: "I"),
            KeyGridItem(id: 31, name: "O"), KeyGridItem(id: 35, name: "P"),
        ],
        // 字母键 - 第二行 (ASDFGHJKL)
        [
            KeyGridItem(id: 0, name: "A"), KeyGridItem(id: 1, name: "S"),
            KeyGridItem(id: 2, name: "D"), KeyGridItem(id: 3, name: "F"),
            KeyGridItem(id: 5, name: "G"), KeyGridItem(id: 4, name: "H"),
            KeyGridItem(id: 38, name: "J"), KeyGridItem(id: 40, name: "K"),
            KeyGridItem(id: 37, name: "L"),
        ],
        // 字母键 - 第三行 (ZXCVBNM)
        [
            KeyGridItem(id: 6, name: "Z"), KeyGridItem(id: 7, name: "X"),
            KeyGridItem(id: 8, name: "C"), KeyGridItem(id: 9, name: "V"),
            KeyGridItem(id: 11, name: "B"), KeyGridItem(id: 45, name: "N"),
            KeyGridItem(id: 46, name: "M"),
        ],
        // 数字键
        [
            KeyGridItem(id: 18, name: "1"), KeyGridItem(id: 19, name: "2"),
            KeyGridItem(id: 20, name: "3"), KeyGridItem(id: 21, name: "4"),
            KeyGridItem(id: 23, name: "5"), KeyGridItem(id: 22, name: "6"),
            KeyGridItem(id: 26, name: "7"), KeyGridItem(id: 28, name: "8"),
            KeyGridItem(id: 25, name: "9"), KeyGridItem(id: 29, name: "0"),
        ],
        // 符号键
        [
            KeyGridItem(id: 50, name: "`"),
            KeyGridItem(id: 27, name: "-"), KeyGridItem(id: 24, name: "="),
            KeyGridItem(id: 33, name: "["), KeyGridItem(id: 30, name: "]"),
            KeyGridItem(id: 42, name: "\\"), KeyGridItem(id: 41, name: ";"),
            KeyGridItem(id: 39, name: "'"), KeyGridItem(id: 43, name: ","),
            KeyGridItem(id: 47, name: "."), KeyGridItem(id: 44, name: "/"),
        ],
        // 功能键
        [
            KeyGridItem(id: 36, name: "↩"), KeyGridItem(id: 51, name: "⌫"),
            KeyGridItem(id: 53, name: "Esc"), KeyGridItem(id: 48, name: "Tab"),
            KeyGridItem(id: 49, name: "Space"),
        ],
        // 方向键
        [
            KeyGridItem(id: 123, name: "←"), KeyGridItem(id: 124, name: "→"),
            KeyGridItem(id: 126, name: "↑"), KeyGridItem(id: 125, name: "↓"),
        ],
    ]
}

// MARK: - KeyPickerView
// 按键自定义选择器主视图。
// 提供原生风格的按键选择界面，支持两个层级的按键选择：
// - 主按键选择：从按键网格中选择主要按键（字母、数字、功能键等）
// - 辅助修饰键选择：动态添加/移除修饰键（⌘⌃⌥⇧），支持任意数量扩展
//
// 界面结构：
// 1. 修饰键区域：动态列表 + 添加按钮，每个修饰键可独立移除
// 2. 按键网格：按 QWERTY 布局组织的按键按钮
// 3. 组合预览：实时显示当前选择的按键组合
// 4. 确认/取消按钮

struct KeyPickerView: View {
    // 选中的按键组合输出绑定
    @Binding var selection: (UInt16, UInt64)?
    // Option/Command 的左右侧选择
    @Binding var modifierSides: ModifierSideSelection
    @Binding var action: MappingAction
    var allowsModifierOnly = false
    var allowsBlocking = false
    @State private var selectedAction: MappingAction = .remap
    // 当前选中的主按键 keyCode
    @State private var selectedKeyCode: UInt16? = nil
    // 当前选中的修饰键列表（动态扩展）
    @State private var modifierKeys: [ModifierKey] = []
    // 是否显示添加修饰键的菜单
    @State private var showAddModifierMenu = false
    // 关闭回调
    var onDismiss: (() -> Void)? = nil
    // 确认回调
    var onConfirm: (() -> Void)? = nil

    init(
        selection: Binding<(UInt16, UInt64)?>,
        modifierSides: Binding<ModifierSideSelection> = .constant(.any),
        allowsModifierOnly: Bool = false,
        action: Binding<MappingAction> = .constant(.remap),
        allowsBlocking: Bool = false,
        onDismiss: (() -> Void)? = nil,
        onConfirm: (() -> Void)? = nil
    ) {
        _selection = selection
        _modifierSides = modifierSides
        _action = action
        self.allowsModifierOnly = allowsModifierOnly
        self.allowsBlocking = allowsBlocking
        self.onDismiss = onDismiss
        self.onConfirm = onConfirm
    }

    // 可添加的修饰键（排除已选中的）
    private var availableModifiers: [ModifierKey] {
        ModifierKey.allCases.filter { mod in
            !modifierKeys.contains(mod)
        }
    }

    // 当前组合的 flags 值（所有修饰键标志位按位或）
    private var combinedFlags: UInt64 {
        modifierKeys.reduce(0) { $0 | $1.flagValue }
    }

    private var resolvedSelection: (UInt16, UInt64)? {
        if allowsBlocking && selectedAction == .block { return (0, 0) }
        if let code = selectedKeyCode { return (code, combinedFlags) }
        guard allowsModifierOnly, modifierKeys.count == 1,
              let modifier = modifierKeys.first else { return nil }
        return (PhysicalModifierKey.keyCode(for: modifier, side: .left), 0)
    }

    private var combinationName: String {
        if allowsBlocking && selectedAction == .block { return NSLocalizedString("rules.block.key", comment: "") }
        guard let (code, flags) = resolvedSelection else { return "" }
        return MyMap.getName(code, flags, modifierSides)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题栏
            HStack {
                Text(NSLocalizedString("keypicker.title", comment: ""))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            if allowsBlocking {
                Picker(NSLocalizedString("keypicker.action", comment: ""), selection: $selectedAction) {
                    Text(NSLocalizedString("keypicker.action.remap", comment: "")).tag(MappingAction.remap)
                    Text(NSLocalizedString("rules.block.key", comment: "")).tag(MappingAction.block)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if selectedAction == .block && allowsBlocking {
                Label(NSLocalizedString("keypicker.block.hint", comment: ""), systemImage: "nosign")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // MARK: 修饰键区域
                modifierSection
                Divider()
                keyGridSection
            }

            Divider()

            // MARK: 组合预览与操作按钮
            previewAndButtonsSection
        }
        .padding(16)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            loadSelection()
        }
    }

    // MARK: - 修饰键区域

    private var modifierSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("keypicker.modifiers", comment: ""))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            // 快捷切换按钮行：四个修饰键的 toggle 按钮
            HStack(spacing: 6) {
                ForEach(ModifierKey.allCases) { mod in
                    Button(action: { toggleModifier(mod) }) {
                        VStack(spacing: 2) {
                            Text(mod.symbol)
                                .font(.system(size: 16, weight: .medium))
                            Text(mod.displayName)
                                .font(.system(size: 9))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(modifierKeys.contains(mod) ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                        )
                        .foregroundColor(modifierKeys.contains(mod) ? .white : .primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(modifierKeys.contains(mod) ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if allowsModifierOnly {
                Text(NSLocalizedString("modifiers.picker.hint", comment: ""))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            if !(allowsModifierOnly && selectedKeyCode == nil)
                && (modifierKeys.contains(.option) || modifierKeys.contains(.command)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("keypicker.side", comment: ""))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    if modifierKeys.contains(.option) {
                        sidePicker(for: .option)
                    }
                    if modifierKeys.contains(.command) {
                        sidePicker(for: .command)
                    }
                }
            }

            // 动态修饰键列表：每个已添加的修饰键显示为可移除的标签
            if !modifierKeys.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(modifierKeys.enumerated()), id: \.offset) { index, mod in
                        HStack(spacing: 8) {
                            Text(mod.symbol)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.accentColor)
                            Text(mod.displayName)
                                .font(.system(size: 12))
                            Spacer()
                            Text(NSLocalizedString("keypicker.layer", comment: "") + " \(index + 1)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Button(action: { removeModifier(at: index) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
                        )
                    }

                    // 添加辅助修饰键按钮
                    if !availableModifiers.isEmpty {
                        Menu {
                            ForEach(availableModifiers) { mod in
                                Button(action: { addModifier(mod) }) {
                                    HStack {
                                        Text(mod.symbol)
                                        Text(mod.displayName)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 11))
                                Text(NSLocalizedString("keypicker.add.modifier", comment: ""))
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.accentColor)
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
            }
        }
    }

    // MARK: - 按键网格区域

    private var keyGridSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("keypicker.key", comment: ""))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 4) {
                    ForEach(Array(KeyGridItem.organizedRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 3) {
                            ForEach(row) { item in
                                Button(action: { selectedKeyCode = selectedKeyCode == item.id ? nil : item.id }) {
                                    Text(item.name)
                                        .font(.system(size: 12, weight: selectedKeyCode == item.id ? .semibold : .regular))
                                        .frame(maxWidth: .infinity, minHeight: 28)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(selectedKeyCode == item.id ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                                        )
                                        .foregroundColor(selectedKeyCode == item.id ? .white : .primary)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .strokeBorder(selectedKeyCode == item.id ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 0.5)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            // 切回映射模式时必须提供明确高度，避免 popover 沿用缩小后的布局将滚动区压成 0。
            .frame(height: 180)
        }
    }

    // MARK: - 组合预览与操作按钮

    private var previewAndButtonsSection: some View {
        VStack(spacing: 12) {
            // 组合预览
            HStack {
                Text(NSLocalizedString("keypicker.preview", comment: ""))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                if resolvedSelection != nil {
                    Text(combinationName.trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                } else {
                    Text(NSLocalizedString("keypicker.no.selection", comment: ""))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // 操作按钮
            HStack {
                Button(action: {
                    onDismiss?()
                }) {
                    Text(NSLocalizedString("keypicker.cancel", comment: ""))
                        .font(.system(size: 12))
                        .frame(width: 80)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: confirmSelection) {
                    Text(NSLocalizedString("keypicker.confirm", comment: ""))
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 80)
                }
                .buttonStyle(.borderedProminent)
                .disabled(resolvedSelection == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - 操作方法

    private func sidePicker(for modifier: ModifierKey) -> some View {
        HStack(spacing: 8) {
            Text(modifier.symbol + " " + modifier.displayName)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 86, alignment: .leading)

            Picker("", selection: Binding(
                get: { modifierSides.side(for: modifier) },
                set: { modifierSides.setSide($0, for: modifier) }
            )) {
                Text(NSLocalizedString("keypicker.side.any", comment: "")).tag(ModifierSide.any)
                Text(NSLocalizedString("keypicker.side.left", comment: "")).tag(ModifierSide.left)
                Text(NSLocalizedString("keypicker.side.right", comment: "")).tag(ModifierSide.right)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func toggleModifier(_ mod: ModifierKey) {
        if let index = modifierKeys.firstIndex(of: mod) {
            modifierKeys.remove(at: index)
            modifierSides.setSide(.any, for: mod)
        } else {
            modifierKeys.append(mod)
        }
    }

    private func addModifier(_ mod: ModifierKey) {
        if !modifierKeys.contains(mod) {
            modifierKeys.append(mod)
        }
    }

    private func removeModifier(at index: Int) {
        guard index < modifierKeys.count else { return }
        modifierSides.setSide(.any, for: modifierKeys[index])
        modifierKeys.remove(at: index)
    }

    // 确认选择：将修饰键和主按键组合为 (keyCode, flags) 并写入绑定变量
    private func confirmSelection() {
        guard let value = resolvedSelection else { return }
        action = allowsBlocking ? selectedAction : .remap
        selection = value
        if action == .block || ModifierMapping.modifier(in: value) != nil { modifierSides = .any }
        onConfirm?()
    }

    // 加载初始状态：从 selection 参数解析当前按键组合
    // 当selection为nil时保持空白状态，确保录制栏为空时选择器也为空
    private func loadSelection() {
        selectedAction = allowsBlocking ? action : .remap
        if selectedAction == .block {
            selectedKeyCode = nil
            modifierKeys = []
            return
        }
        if let sel = selection {
            let (code, flags) = sel
            if allowsModifierOnly, let modifier = ModifierMapping.modifier(in: sel) {
                selectedKeyCode = nil
                modifierKeys = [modifier]
                modifierSides = .any
                return
            }
            selectedKeyCode = code
            modifierKeys = parseModifiersFromFlags(flags)
            if !modifierKeys.contains(.option) { modifierSides.option = .any }
            if !modifierKeys.contains(.command) { modifierSides.command = .any }
        } else {
            selectedKeyCode = nil
            modifierKeys = []
            modifierSides = .any
        }
    }

    // 从CGEventFlags位掩码解析出修饰键列表
    private func parseModifiersFromFlags(_ flags: UInt64) -> [ModifierKey] {
        var result: [ModifierKey] = []
        let modifiers: [(ModifierKey, UInt64)] = [
            (.control, 0x40000),
            (.option, 0x80000),
            (.shift, 0x20000),
            (.command, 0x100000)
        ]
        for (mod, flag) in modifiers {
            if flags & flag != 0 {
                result.append(mod)
            }
        }
        return result
    }

}
