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
        return []
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
