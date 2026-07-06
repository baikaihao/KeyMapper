import Foundation

class MappingStore {
    static let shared = MappingStore()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let maps = "saved_maps"
        static let pauseHotkey = "setting_pause_hotkey"
        static let blacklist = "setting_blacklist"
        static let globalBlacklistMigrated = "setting_global_blacklist_migrated_to_rules"
    }

    static let defaultPauseHotkey: (keyCode: UInt16, flags: UInt64) = (6, 0x120000)

    static func defaultMappings() -> [MyMap] {
        [
            MyMap(
                id: UUID(uuidString: "83B101D3-5991-4D06-ABC8-9FB2A87CDCAA") ?? UUID(),
                fCode: 8,
                fFlags: ModifierKey.control.flagValue,
                tCode: 8,
                tFlags: ModifierKey.command.flagValue,
                note: NSLocalizedString("default.rule.copy", comment: ""),
                appBlacklist: ["com.apple.Terminal"]
            ),
            MyMap(
                id: UUID(uuidString: "84CE3354-FDD0-4024-86F3-A7BA07993DD2") ?? UUID(),
                fCode: 0,
                fFlags: ModifierKey.control.flagValue,
                tCode: 0,
                tFlags: ModifierKey.command.flagValue,
                note: NSLocalizedString("default.rule.select.all", comment: "")
            ),
            MyMap(
                id: UUID(uuidString: "B84B8EC3-FF46-4118-B1E8-D9723512884C") ?? UUID(),
                fCode: 9,
                fFlags: ModifierKey.control.flagValue,
                tCode: 9,
                tFlags: ModifierKey.command.flagValue,
                note: NSLocalizedString("default.rule.paste", comment: "")
            ),
            MyMap(
                id: UUID(uuidString: "42493CD9-8773-4F07-AB5A-DCCB42BBE454") ?? UUID(),
                fCode: 2,
                fFlags: ModifierKey.control.flagValue,
                tCode: 51,
                tFlags: ModifierKey.command.flagValue,
                note: NSLocalizedString("default.rule.delete.file", comment: "")
            ),
            MyMap(
                id: UUID(uuidString: "19873499-6097-41FB-B378-4B8E75163907") ?? UUID(),
                fCode: 6,
                fFlags: ModifierKey.control.flagValue,
                tCode: 6,
                tFlags: ModifierKey.command.flagValue,
                note: NSLocalizedString("default.rule.undo", comment: "")
            ),
            MyMap(
                id: UUID(uuidString: "A04D98BF-ADA1-4DE6-AA97-248AD88B7C63") ?? UUID(),
                fCode: 7,
                fFlags: ModifierKey.control.flagValue,
                tCode: 7,
                tFlags: ModifierKey.command.flagValue,
                note: NSLocalizedString("default.rule.cut", comment: "")
            )
        ]
    }

    func saveList(_ list: [MyMap]) {
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: Key.maps)
        }
    }

    func loadList() -> [MyMap] {
        if let data = defaults.data(forKey: Key.maps),
           let decoded = try? JSONDecoder().decode([MyMap].self, from: data) {
            return decoded
        }
        return Self.defaultMappings()
    }

    func savePauseHotkey(_ hotkey: (keyCode: UInt16, flags: UInt64)?) {
        if let hk = hotkey {
            let dict: [String: Any] = ["keyCode": Int(hk.keyCode), "flags": Int(hk.flags)]
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                defaults.set(data, forKey: Key.pauseHotkey)
            }
        } else {
            defaults.removeObject(forKey: Key.pauseHotkey)
        }
    }

    func loadPauseHotkey() -> (keyCode: UInt16, flags: UInt64)? {
        if let data = defaults.data(forKey: Key.pauseHotkey),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let keyCode = dict["keyCode"] as? Int,
           let flags = dict["flags"] as? Int {
            return (keyCode: UInt16(keyCode), flags: UInt64(flags))
        }
        return Self.defaultPauseHotkey
    }

    func saveBlacklist(_ blacklist: [String]) {
        if let data = try? JSONEncoder().encode(blacklist) {
            defaults.set(data, forKey: Key.blacklist)
        }
    }

    func loadBlacklist() -> [String] {
        if let data = defaults.data(forKey: Key.blacklist),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
        }
        return []
    }

    func clearBlacklist() {
        defaults.removeObject(forKey: Key.blacklist)
    }

    func hasMigratedGlobalBlacklist() -> Bool {
        defaults.bool(forKey: Key.globalBlacklistMigrated)
    }

    func markGlobalBlacklistMigrated() {
        defaults.set(true, forKey: Key.globalBlacklistMigrated)
    }
}
