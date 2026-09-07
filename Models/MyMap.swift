import SwiftUI
import CoreGraphics

// 修饰键的物理侧别。旧规则使用 .any，表示只匹配聚合的修饰键标志，不限制左右。
enum ModifierSide: String, CaseIterable, Codable, Hashable {
    case any
    case left
    case right

    var shortName: String {
        switch self {
        case .any: return ""
        case .left: return "L"
        case .right: return "R"
        }
    }
}

// Option 和 Command 的左右侧选择。Control/Shift 继续使用原有的通用 flags。
struct ModifierSideSelection: Codable, Equatable, Hashable {
    var option: ModifierSide = .any
    var command: ModifierSide = .any

    static let any = ModifierSideSelection()

    func side(for modifier: ModifierKey) -> ModifierSide {
        switch modifier {
        case .option: return option
        case .command: return command
        case .control, .shift: return .any
        }
    }

    mutating func setSide(_ side: ModifierSide, for modifier: ModifierKey) {
        switch modifier {
        case .option: option = side
        case .command: command = side
        case .control, .shift: break
        }
    }
}

// macOS 虚拟键码中的左右修饰键。CGEventFlags 只有聚合标志，因此运行时必须保留这些物理键码。
enum PhysicalModifierKey {
    static let codes: [ModifierKey: (left: UInt16, right: UInt16)] = [
        .control: (59, 62),
        .shift: (56, 60),
        .option: (58, 61),
        .command: (55, 54)
    ]

    static func modifier(for keyCode: UInt16) -> (modifier: ModifierKey, side: ModifierSide)? {
        for (modifier, pair) in codes {
            if keyCode == pair.left { return (modifier, .left) }
            if keyCode == pair.right { return (modifier, .right) }
        }
        return nil
    }

    static func keyCode(for modifier: ModifierKey, side: ModifierSide) -> UInt16 {
        let pair = codes[modifier]!
        return side == .right ? pair.right : pair.left
    }
}

// 记录当前物理修饰键按下状态，供录制和事件映射共同使用。
final class ModifierSideTracker {
    static let shared = ModifierSideTracker()

    private(set) var heldKeyCodes: Set<UInt16> = []

    func updateFlagsChanged(keyCode: UInt16, flags: UInt64) {
        guard PhysicalModifierKey.modifier(for: keyCode) != nil else { return }
        // flagsChanged 的 flags 是聚合值。单侧切换可直接从聚合值判断；两侧同时按下时再查询物理键状态。
        guard let descriptor = PhysicalModifierKey.modifier(for: keyCode) else { return }
        let pair = PhysicalModifierKey.codes[descriptor.modifier]!
        let otherCode = keyCode == pair.left ? pair.right : pair.left
        let aggregatePressed = (flags & descriptor.modifier.flagValue) != 0
        let currentPressed = heldKeyCodes.contains(keyCode)
        let otherPressed = heldKeyCodes.contains(otherCode)

        if aggregatePressed && currentPressed && !otherPressed {
            // 同一事件可能同时经过 event tap 和录制视图，避免重复处理把状态反转。
            return
        } else if !aggregatePressed && !currentPressed {
            return
        } else if aggregatePressed && !currentPressed && !otherPressed {
            update(keyCode: keyCode, isPressed: true)
        } else if !aggregatePressed && currentPressed {
            update(keyCode: keyCode, isPressed: false)
        } else {
            // 左右同类键同时按下/松开时，聚合 flag 不变，只能查询物理键状态。
            update(
                keyCode: keyCode,
                isPressed: CGEventSource.keyState(.hidSystemState, key: CGKeyCode(keyCode))
            )
        }
    }

    func updateKeyEvent(keyCode: UInt16, isDown: Bool) {
        guard PhysicalModifierKey.modifier(for: keyCode) != nil else { return }
        update(keyCode: keyCode, isPressed: isDown)
    }

    func reset() {
        heldKeyCodes.removeAll()
    }

    func sideSelection(for flags: UInt64) -> ModifierSideSelection {
        var result = ModifierSideSelection.any
        for modifier in [ModifierKey.option, .command] where (flags & modifier.flagValue) != 0 {
            let pair = PhysicalModifierKey.codes[modifier]!
            let side: ModifierSide
            if heldKeyCodes.contains(pair.left) && !heldKeyCodes.contains(pair.right) {
                side = .left
            } else if heldKeyCodes.contains(pair.right) && !heldKeyCodes.contains(pair.left) {
                side = .right
            } else {
                side = .any
            }
            result.setSide(side, for: modifier)
        }
        return result
    }

    func physicalCodes(for flags: UInt64) -> Set<UInt16> {
        var result = Set<UInt16>()
        for modifier in ModifierKey.allCases where (flags & modifier.flagValue) != 0 {
            let pair = PhysicalModifierKey.codes[modifier]!
            let held = heldKeyCodes.filter { $0 == pair.left || $0 == pair.right }
            if held.isEmpty {
                result.insert(pair.left)
            } else {
                result.formUnion(held)
            }
        }
        return result
    }

    private func update(keyCode: UInt16, isPressed: Bool) {
        if isPressed {
            heldKeyCodes.insert(keyCode)
        } else {
            heldKeyCodes.remove(keyCode)
        }
    }
}

// MARK: - MyMap
// 键盘映射规则数据模型。
// 每条规则定义了一个按键映射关系：源按键（from）→ 目标按键（to）。
//
// 属性说明：
// - fCode/fFlags: 源按键的 keyCode 和修饰键标志位
// - tCode/tFlags: 目标按键的 keyCode 和修饰键标志位
// - isOn: 该规则是否启用
// - note: 用户自定义备注
// - appBlacklist: 该规则在哪些应用中不执行
//
// flags 位掩码说明（CGEventFlags）：
// - 0x40000: Control 键
// - 0x80000: Option/Alt 键
// - 0x20000: Shift 键
// - 0x100000: Command 键

struct MyMap: Identifiable, Codable {
    var id = UUID()
    // 源按键 keyCode（macOS 虚拟键码）
    var fCode: UInt16
    // 源按键修饰键标志位
    var fFlags: UInt64
    // 源按键 Option/Command 的物理侧别
    var fModifierSides: ModifierSideSelection
    // 目标按键 keyCode
    var tCode: UInt16
    // 目标按键修饰键标志位
    var tFlags: UInt64
    // 目标按键 Option/Command 的物理侧别
    var tModifierSides: ModifierSideSelection
    // 是否启用该映射规则
    var isOn: Bool = true
    // 用户备注
    var note: String = ""
    // 规则级应用黑名单：当前台应用 Bundle ID 在列表中时，该规则不执行
    var appBlacklist: [String] = []

    enum CodingKeys: String, CodingKey {
        case id, fCode, fFlags, fModifierSides, tCode, tFlags, tModifierSides, isOn, note, appBlacklist
    }

    // 完整初始化器，支持指定所有属性
    init(id: UUID = UUID(), fCode: UInt16, fFlags: UInt64, tCode: UInt16, tFlags: UInt64, fModifierSides: ModifierSideSelection = .any, tModifierSides: ModifierSideSelection = .any, isOn: Bool = true, note: String = "", appBlacklist: [String] = []) {
        self.id = id
        self.fCode = fCode
        self.fFlags = fFlags
        self.fModifierSides = fModifierSides
        self.tCode = tCode
        self.tFlags = tFlags
        self.tModifierSides = tModifierSides
        self.isOn = isOn
        self.note = note
        self.appBlacklist = appBlacklist
    }

    // 便捷初始化器，用于新增映射时自动生成 id，默认启用
    init(fCode: UInt16, fFlags: UInt64, tCode: UInt16, tFlags: UInt64, fModifierSides: ModifierSideSelection = .any, tModifierSides: ModifierSideSelection = .any, note: String = "", appBlacklist: [String] = []) {
        self.fCode = fCode
        self.fFlags = fFlags
        self.fModifierSides = fModifierSides
        self.tCode = tCode
        self.tFlags = tFlags
        self.tModifierSides = tModifierSides
        self.note = note
        self.appBlacklist = appBlacklist
    }

    // 自定义解码用于兼容旧版本保存的规则数据。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fCode = try container.decode(UInt16.self, forKey: .fCode)
        fFlags = try container.decode(UInt64.self, forKey: .fFlags)
        fModifierSides = try container.decodeIfPresent(ModifierSideSelection.self, forKey: .fModifierSides) ?? .any
        tCode = try container.decode(UInt16.self, forKey: .tCode)
        tFlags = try container.decode(UInt64.self, forKey: .tFlags)
        tModifierSides = try container.decodeIfPresent(ModifierSideSelection.self, forKey: .tModifierSides) ?? .any
        isOn = try container.decodeIfPresent(Bool.self, forKey: .isOn) ?? true
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        appBlacklist = try container.decodeIfPresent([String].self, forKey: .appBlacklist) ?? []
    }

    // MARK: - 按键名称转换

    // 将 keyCode + flags 转换为人类可读的字符串表示。
    // 修饰键按 Control → Option → Shift → Command 顺序拼接符号，
    // 然后追加按键名称，例如 "⌃ ⌥ ⇧ ⌘ Z"。
    // 无法识别的 keyCode 显示为 "K{code}"。
    static let keyMap: [UInt16: String] = [
        0:  "A ", 1:  "S ", 2:  "D ", 3:  "F ", 4:  "H ", 5:  "G ", 6:  "Z ", 7:  "X ", 8:  "C ", 9:  "V ",
        11:  "B ", 12:  "Q ", 13:  "W ", 14:  "E ", 15:  "R ", 16:  "Y ", 17:  "T ", 18:  "1 ", 19:  "2 ",
        20:  "3 ", 21:  "4 ", 22:  "6 ", 23:  "5 ", 24:  "= ", 25:  "9 ", 26:  "7 ", 27:  "-", 28:  "8 ",
        29:  "0 ", 30:  "] ", 31:  "O ", 32:  "U ", 33:  "[ ", 34:  "I ", 35:  "P ", 37:  "L ", 38:  "J ",
        39:  "' ", 40:  "K ", 41:  "; ", 42:  "\\ ", 43:  ", ", 44:  "/ ", 45:  "N ", 46:  "M ", 47:  ". ",
        48:  "Tab ", 49:  "Space ", 36:  "↩ ", 51:  "⌫ ", 53:  "Esc ",
        123:  "← ", 124:  "→ ", 125:  "↓ ", 126:  "↑ "
    ]

    static func getName(_ c: UInt16, _ f: UInt64, _ sides: ModifierSideSelection = .any) -> String {
        var s = " "
        for mod in ModifierKey.allCases {
            if (f & mod.flagValue) != 0 {
                let side = sides.side(for: mod)
                let sideLabel = side == .any ? "" : "(\(side.shortName))"
                s += mod.symbol + sideLabel + " "
            }
        }

        return s + (keyMap[c] ?? "K\(c) ")
    }
}

extension Date {
    var formattedMedium: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}
