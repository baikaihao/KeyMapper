import Foundation

// MARK: - ModifierKey
// 修饰键枚举，表示 macOS 的四个标准修饰键。
// 每个修饰键关联其符号、显示名称和 CGEventFlags 位掩码值。

enum ModifierKey: String, CaseIterable, Identifiable, Codable {
    case control = "control"
    case option = "option"
    case shift = "shift"
    case command = "command"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        }
    }

    var displayName: String {
        switch self {
        case .control: return "Control"
        case .option: return "Option"
        case .shift: return "Shift"
        case .command: return "Command"
        }
    }

    var flagValue: UInt64 {
        switch self {
        case .control: return 0x40000
        case .option: return 0x80000
        case .shift: return 0x20000
        case .command: return 0x100000
        }
    }

    static let allMask: UInt64 = ModifierKey.allCases.reduce(0) { $0 | $1.flagValue }
}

// 独立于快捷键的修饰键规则；同时映射左右两侧并保留物理侧别。
struct ModifierMapping: Identifiable, Codable, Equatable {
    var id = UUID()
    var source: ModifierKey
    var target: ModifierKey
    var isOn = true
    var note = ""
    var appBlacklist: [String] = []
    var createdAt: Date? = Date()

    static func modifier(in selection: (UInt16, UInt64)) -> ModifierKey? {
        guard selection.1 == 0 else { return nil }
        return PhysicalModifierKey.modifier(for: selection.0)?.modifier
    }

    // 与普通快捷键共用同一种规则卡片和录入值，事件处理仍使用独立的修饰键状态。
    var rule: MyMap {
        MyMap(
            id: id, fCode: PhysicalModifierKey.keyCode(for: source, side: .left), fFlags: 0,
            tCode: PhysicalModifierKey.keyCode(for: target, side: .left), tFlags: 0,
            isOn: isOn, note: note, appBlacklist: appBlacklist, createdAt: createdAt
        )
    }
}

extension ModifierMapping {
    private enum CodingKeys: String, CodingKey {
        case id, source, target, isOn, note, appBlacklist, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        source = try container.decode(ModifierKey.self, forKey: .source)
        target = try container.decode(ModifierKey.self, forKey: .target)
        isOn = try container.decode(Bool.self, forKey: .isOn)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        appBlacklist = try container.decode([String].self, forKey: .appBlacklist)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

// 单个修饰键在松开时提交，按下时继续等待，保证 Ctrl+C 不会被提前录成 Ctrl。
struct ModifierKeyRecording {
    private var held = Set<UInt16>()
    private var candidate: UInt16?
    private var isChord = false

    mutating func begin(held: Set<UInt16> = []) {
        self.held = held
        candidate = nil
        isChord = !held.isEmpty
    }

    mutating func update(keyCode: UInt16, isDown: Bool) -> UInt16? {
        guard PhysicalModifierKey.modifier(for: keyCode) != nil else { return nil }
        if isDown {
            guard held.insert(keyCode).inserted else { return nil }
            if held.count == 1 && !isChord {
                candidate = keyCode
            } else {
                candidate = nil
                isChord = true
            }
            return nil
        }
        guard held.remove(keyCode) != nil, held.isEmpty else { return nil }
        let result = !isChord && candidate == keyCode ? candidate : nil
        begin()
        return result
    }
}
