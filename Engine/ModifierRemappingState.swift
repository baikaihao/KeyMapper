import Foundation

// 纯状态计算：每个物理键只查一次规则，交换不会递归，多个来源共享目标时不会提前松开。
struct ModifierRemappingState {
    struct Change: Equatable {
        let keyCode: UInt16
        let isDown: Bool
        let flags: UInt64
    }

    private(set) var outputCodes: Set<UInt16> = []
    private static let orderedCodes: [UInt16] = [56, 60, 59, 62, 58, 61, 55, 54]
    private static let deviceFlags: [UInt16: UInt64] = [
        59: 0x0001, 62: 0x2000, 56: 0x0002, 60: 0x0004,
        55: 0x0008, 54: 0x0010, 58: 0x0020, 61: 0x0040
    ]

    // 只有唯一且目标也是修饰键的规则才直接改写持续状态；其他规则走按下/松开或轮盘。
    static func continuousRules(from rules: [MyMap]) -> [ModifierMapping] {
        var grouped: [ModifierKey: [MyMap]] = [:]
        for rule in rules {
            if let source = rule.sourceModifier { grouped[source, default: []].append(rule) }
        }
        return grouped.compactMap { source, matches in
            guard matches.count == 1, let rule = matches.first, let target = rule.targetModifier else { return nil }
            return ModifierMapping(id: rule.id, source: source, target: target, note: rule.note, appBlacklist: rule.appBlacklist)
        }
    }

    static func mappedCodes(
        _ physicalCodes: Set<UInt16>,
        rules: [ModifierMapping],
        bundleID: String?,
        enabled: Bool
    ) -> Set<UInt16> {
        guard enabled else { return physicalCodes }
        return Set(physicalCodes.map { code in
            guard let physical = PhysicalModifierKey.modifier(for: code),
                  let rule = rules.first(where: {
                      $0.isOn && $0.source == physical.modifier
                  }) else { return code }
            // 无 bundle ID 的前台应用同样可以映射；黑名单仅匹配已知 ID。
            if let bundleID, rule.appBlacklist.contains(bundleID) { return code }
            return PhysicalModifierKey.keyCode(for: rule.target, side: physical.side)
        })
    }

    static func flags(for codes: Set<UInt16>, preserving flags: UInt64) -> UInt64 {
        let deviceMask = deviceFlags.values.reduce(0, |)
        return codes.reduce(flags & ~(ModifierKey.allMask | deviceMask)) { value, code in
            guard let modifier = PhysicalModifierKey.modifier(for: code)?.modifier else { return value }
            return value | modifier.flagValue | (deviceFlags[code] ?? 0)
        }
    }

    static func applyingShortcuts(
        to codes: Set<UInt16>,
        overrides: [(source: Set<UInt16>, target: Set<UInt16>)]
    ) -> Set<UInt16> {
        var result = codes
        for override in overrides { result.subtract(override.source) }
        for override in overrides { result.formUnion(override.target) }
        return result
    }

    mutating func synchronize(to codes: Set<UInt16>) {
        outputCodes = codes
    }

    mutating func transition(to codes: Set<UInt16>, preserving flags: UInt64 = 0) -> [Change] {
        var changes: [Change] = []
        for code in Self.orderedCodes.reversed() where outputCodes.contains(code) && !codes.contains(code) {
            outputCodes.remove(code)
            changes.append(Change(keyCode: code, isDown: false, flags: Self.flags(for: outputCodes, preserving: flags)))
        }
        for code in Self.orderedCodes where !outputCodes.contains(code) && codes.contains(code) {
            outputCodes.insert(code)
            changes.append(Change(keyCode: code, isDown: true, flags: Self.flags(for: outputCodes, preserving: flags)))
        }
        return changes
    }
}
