import SwiftUI

// MARK: - MyMap
// 键盘映射规则数据模型。
// 每条规则定义了一个按键映射关系：源按键（from）→ 目标按键（to）。
//
// 属性说明：
// - fCode/fFlags: 源按键的 keyCode 和修饰键标志位
// - tCode/tFlags: 目标按键的 keyCode 和修饰键标志位
// - isOn: 该规则是否启用
// - note: 用户自定义备注
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
    // 目标按键 keyCode
    var tCode: UInt16
    // 目标按键修饰键标志位
    var tFlags: UInt64
    // 是否启用该映射规则
    var isOn: Bool = true
    // 用户备注
    var note: String = ""

    enum CodingKeys: String, CodingKey {
        case id, fCode, fFlags, tCode, tFlags, isOn, note
    }

    // 完整初始化器，支持指定所有属性
    init(id: UUID = UUID(), fCode: UInt16, fFlags: UInt64, tCode: UInt16, tFlags: UInt64, isOn: Bool = true, note: String = "") {
        self.id = id
        self.fCode = fCode
        self.fFlags = fFlags
        self.tCode = tCode
        self.tFlags = tFlags
        self.isOn = isOn
        self.note = note
    }

    // 便捷初始化器，用于新增映射时自动生成 id，默认启用
    init(fCode: UInt16, fFlags: UInt64, tCode: UInt16, tFlags: UInt64, note: String = "") {
        self.fCode = fCode
        self.fFlags = fFlags
        self.tCode = tCode
        self.tFlags = tFlags
        self.note = note
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
        49:  "Space ", 36:  "↩ ", 51:  "⌫ ", 53:  "Esc ", 48:  "Tab ",
        123:  "← ", 124:  "→ ", 125:  "↓ ", 126:  "↑ "
    ]

    static func getName(_ c: UInt16, _ f: UInt64) -> String {
        var s = " "
        for mod in ModifierKey.allCases {
            if (f & mod.flagValue) != 0 { s += mod.symbol + " " }
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
