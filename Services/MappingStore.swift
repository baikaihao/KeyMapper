import Foundation

class MappingStore {
    static let shared = MappingStore()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let maps = "saved_maps"
        static let pauseHotkey = "setting_pause_hotkey"
        static let blacklist = "setting_blacklist"
        static let globalBlacklistSeparated = "setting_global_blacklist_separated_from_rules_v1"
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
            if let data = try? JSONEncoder().encode(HotkeyRecord(hk)) {
                defaults.set(data, forKey: Key.pauseHotkey)
            }
        } else {
            defaults.removeObject(forKey: Key.pauseHotkey)
        }
    }

    func loadPauseHotkey() -> (keyCode: UInt16, flags: UInt64)? {
        guard let data = defaults.data(forKey: Key.pauseHotkey),
              let record = try? JSONDecoder().decode(HotkeyRecord.self, from: data),
              Self.isValidKeyCode(record.keyCode),
              Self.isValidFlags(record.flags) else {
            return Self.defaultPauseHotkey
        }

        return (keyCode: record.keyCode, flags: record.flags)
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

    func hasSeparatedGlobalBlacklistFromRules() -> Bool {
        defaults.bool(forKey: Key.globalBlacklistSeparated)
    }

    func markGlobalBlacklistSeparatedFromRules() {
        defaults.set(true, forKey: Key.globalBlacklistSeparated)
    }
}

// MARK: - Versioned import and export

extension MappingStore {
    struct Configuration: Codable {
        static let currentVersion = "2.0"

        let version: String
        let mappings: [MappingRecord]
        let blacklist: [String]
        let pauseHotkey: HotkeyRecord?

        private enum CodingKeys: String, CodingKey {
            case version, mappings, blacklist, pauseHotkey
        }

        @MainActor
        init(
            mappings: [MyMap],
            blacklist: [String],
            pauseHotkey: (keyCode: UInt16, flags: UInt64)?
        ) {
            version = Self.currentVersion
            self.mappings = mappings.map(MappingRecord.init)
            self.blacklist = blacklist
            self.pauseHotkey = pauseHotkey.map(HotkeyRecord.init)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(String.self, forKey: .version)
            mappings = try container.decode([MappingRecord].self, forKey: .mappings)
            blacklist = try container.decode([String].self, forKey: .blacklist)

            // A missing pauseHotkey field means the document is incomplete. JSON null is
            // decoded separately and rejected during validation because nil is not a
            // persistable pause-hotkey state in the current store.
            guard container.contains(.pauseHotkey) else {
                throw DecodingError.keyNotFound(
                    CodingKeys.pauseHotkey,
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "Missing pauseHotkey"
                    )
                )
            }
            pauseHotkey = try container.decodeIfPresent(HotkeyRecord.self, forKey: .pauseHotkey)
        }
    }

    struct MappingRecord: Codable {
        let id: UUID
        let fCode: UInt16
        let fFlags: UInt64
        let tCode: UInt16
        let tFlags: UInt64
        let isOn: Bool
        let note: String
        let appBlacklist: [String]

        init(_ mapping: MyMap) {
            id = mapping.id
            fCode = mapping.fCode
            fFlags = mapping.fFlags & ModifierKey.allMask
            tCode = mapping.tCode
            tFlags = mapping.tFlags & ModifierKey.allMask
            isOn = mapping.isOn
            note = mapping.note
            appBlacklist = mapping.appBlacklist
        }
    }

    struct HotkeyRecord: Codable {
        let keyCode: UInt16
        let flags: UInt64

        init(_ hotkey: (keyCode: UInt16, flags: UInt64)) {
            keyCode = hotkey.keyCode
            flags = hotkey.flags & ModifierKey.allMask
        }
    }

    struct ValidatedConfiguration {
        let mappings: [MyMap]
        let blacklist: [String]
        let pauseHotkey: (keyCode: UInt16, flags: UInt64)
    }

    enum ConfigurationError: LocalizedError {
        case fileTooLarge
        case invalidFormat
        case unsupportedVersion(String)
        case tooManyMappings
        case duplicateMappingID(UUID)
        case invalidMappingValue(Int)
        case invalidMappingNote(Int)
        case invalidMappingBlacklist(Int)
        case invalidGlobalBlacklist
        case invalidPauseHotkey
        case persistenceFailed

        var errorDescription: String? {
            switch self {
            case .fileTooLarge:
                return NSLocalizedString("settings.import.error.file.too.large", comment: "")
            case .invalidFormat:
                return NSLocalizedString("settings.import.error.invalid.format", comment: "")
            case .unsupportedVersion(let version):
                return String(
                    format: NSLocalizedString("settings.import.error.unsupported.version", comment: ""),
                    version
                )
            case .tooManyMappings:
                return NSLocalizedString("settings.import.error.too.many.mappings", comment: "")
            case .duplicateMappingID(let id):
                return String(
                    format: NSLocalizedString("settings.import.error.duplicate.id", comment: ""),
                    id.uuidString
                )
            case .invalidMappingValue(let index):
                return String(
                    format: NSLocalizedString("settings.import.error.invalid.mapping", comment: ""),
                    index
                )
            case .invalidMappingNote(let index):
                return String(
                    format: NSLocalizedString("settings.import.error.invalid.note", comment: ""),
                    index
                )
            case .invalidMappingBlacklist(let index):
                return String(
                    format: NSLocalizedString("settings.import.error.invalid.rule.blacklist", comment: ""),
                    index
                )
            case .invalidGlobalBlacklist:
                return NSLocalizedString("settings.import.error.invalid.blacklist", comment: "")
            case .invalidPauseHotkey:
                return NSLocalizedString("settings.import.error.invalid.hotkey", comment: "")
            case .persistenceFailed:
                return NSLocalizedString("settings.import.error.persistence", comment: "")
            }
        }
    }

    private static let maximumConfigurationSize = 10 * 1024 * 1024
    private static let maximumMappingCount = 10_000
    private static let maximumBlacklistCount = 2_000
    private static let maximumKeyCode: UInt16 = 127
    private static let modifierOnlyKeyCodes = Set(UInt16(54)...UInt16(63))
    private static let maximumNoteByteCount = 16 * 1024
    private static let maximumBundleIdentifierByteCount = 255

    @MainActor
    static func makeConfiguration(
        mappings: [MyMap],
        blacklist: [String],
        pauseHotkey: (keyCode: UInt16, flags: UInt64)?
    ) -> Configuration {
        Configuration(mappings: mappings, blacklist: blacklist, pauseHotkey: pauseHotkey)
    }

    static func encodeConfiguration(_ configuration: Configuration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(configuration)
    }

    static func encodeValidatedConfiguration(_ configuration: Configuration) throws -> Data {
        let data = try encodeConfiguration(configuration)
        _ = try decodeAndValidateConfiguration(from: data)
        return data
    }

    static func decodeAndValidateConfiguration(from data: Data) throws -> ValidatedConfiguration {
        guard data.count <= maximumConfigurationSize else {
            throw ConfigurationError.fileTooLarge
        }

        let configuration: Configuration
        do {
            configuration = try JSONDecoder().decode(Configuration.self, from: data)
        } catch {
            throw ConfigurationError.invalidFormat
        }

        guard configuration.version == Configuration.currentVersion else {
            throw ConfigurationError.unsupportedVersion(configuration.version)
        }
        guard configuration.mappings.count <= maximumMappingCount else {
            throw ConfigurationError.tooManyMappings
        }

        let globalBlacklist = try validatedBlacklist(
            configuration.blacklist,
            error: .invalidGlobalBlacklist
        )

        var mappingIDs = Set<UUID>()
        var mappings: [MyMap] = []
        mappings.reserveCapacity(configuration.mappings.count)

        for (offset, record) in configuration.mappings.enumerated() {
            let displayIndex = offset + 1

            guard mappingIDs.insert(record.id).inserted else {
                throw ConfigurationError.duplicateMappingID(record.id)
            }
            guard isValidKeyCode(record.fCode),
                  isValidKeyCode(record.tCode),
                  isValidFlags(record.fFlags),
                  isValidFlags(record.tFlags) else {
                throw ConfigurationError.invalidMappingValue(displayIndex)
            }
            guard record.note.utf8.count <= maximumNoteByteCount else {
                throw ConfigurationError.invalidMappingNote(displayIndex)
            }

            let ruleBlacklist = try validatedBlacklist(
                record.appBlacklist,
                error: .invalidMappingBlacklist(displayIndex)
            )

            mappings.append(
                MyMap(
                    id: record.id,
                    fCode: record.fCode,
                    fFlags: record.fFlags,
                    tCode: record.tCode,
                    tFlags: record.tFlags,
                    isOn: record.isOn,
                    note: record.note,
                    appBlacklist: ruleBlacklist
                )
            )
        }

        guard let hotkeyRecord = configuration.pauseHotkey,
              isValidKeyCode(hotkeyRecord.keyCode),
              isValidFlags(hotkeyRecord.flags) else {
            throw ConfigurationError.invalidPauseHotkey
        }

        return ValidatedConfiguration(
            mappings: mappings,
            blacklist: globalBlacklist,
            pauseHotkey: (hotkeyRecord.keyCode, hotkeyRecord.flags)
        )
    }

    static func decodeAndValidateConfiguration(at url: URL) throws -> ValidatedConfiguration {
        if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           fileSize > maximumConfigurationSize {
            throw ConfigurationError.fileTooLarge
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ConfigurationError.invalidFormat
        }
        defer { try? handle.close() }

        var data = Data()
        let readLimit = maximumConfigurationSize + 1
        do {
            while data.count < readLimit {
                let chunkSize = min(64 * 1024, readLimit - data.count)
                guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
                data.append(chunk)
            }
        } catch {
            throw ConfigurationError.invalidFormat
        }

        guard data.count <= maximumConfigurationSize else {
            throw ConfigurationError.fileTooLarge
        }
        return try decodeAndValidateConfiguration(from: data)
    }

    func persistValidatedConfiguration(_ configuration: ValidatedConfiguration) throws {
        let encoder = JSONEncoder()
        let mappingsData = try encoder.encode(configuration.mappings)
        let blacklistData = try encoder.encode(configuration.blacklist)
        let hotkeyData = try encoder.encode(HotkeyRecord(configuration.pauseHotkey))

        guard let domainName = Bundle.main.bundleIdentifier else {
            throw ConfigurationError.persistenceFailed
        }

        let previousDomain = defaults.persistentDomain(forName: domainName)
        var updatedDomain = previousDomain ?? [:]
        updatedDomain[Key.maps] = mappingsData
        updatedDomain[Key.blacklist] = blacklistData
        updatedDomain[Key.pauseHotkey] = hotkeyData
        defaults.setPersistentDomain(updatedDomain, forName: domainName)

        guard defaults.data(forKey: Key.maps) == mappingsData,
              defaults.data(forKey: Key.blacklist) == blacklistData,
              defaults.data(forKey: Key.pauseHotkey) == hotkeyData else {
            if let previousDomain {
                defaults.setPersistentDomain(previousDomain, forName: domainName)
            } else {
                defaults.removePersistentDomain(forName: domainName)
            }
            throw ConfigurationError.persistenceFailed
        }
    }

    private static func isValidKeyCode(_ keyCode: UInt16) -> Bool {
        keyCode <= maximumKeyCode && !modifierOnlyKeyCodes.contains(keyCode)
    }

    private static func isValidFlags(_ flags: UInt64) -> Bool {
        (flags & ~ModifierKey.allMask) == 0
    }

    private static func validatedBlacklist(
        _ blacklist: [String],
        error: ConfigurationError
    ) throws -> [String] {
        guard blacklist.count <= maximumBlacklistCount else { throw error }

        var seen = Set<String>()
        for bundleIdentifier in blacklist {
            let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed == bundleIdentifier,
                  bundleIdentifier.utf8.count <= maximumBundleIdentifierByteCount,
                  !bundleIdentifier.unicodeScalars.contains(where: { $0.value == 0 }),
                  seen.insert(bundleIdentifier).inserted else {
                throw error
            }
        }
        return blacklist
    }
}
