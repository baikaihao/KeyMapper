import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import KeyMapperCore

@Suite @MainActor
struct KeyBlockingTests {
    private final class Context {
        var app = "test.xmind"
        var posted: [CGEvent] = []
    }

    private func block(_ code: UInt16 = 50, flags: UInt64 = 0) -> MyMap {
        MyMap(fCode: code, fFlags: flags, tCode: 0, tFlags: 0, action: .block,
              appFilterMode: .whitelist, appWhitelist: ["test.xmind"])
    }

    private func engine(_ rules: [MyMap], context: Context) -> MyEngine {
        ModifierSideTracker.shared.reset()
        let engine = MyEngine(startMonitoring: false, eventPoster: { event, _ in
            context.posted.append(event)
        }, frontmostBundleID: { context.app })
        engine.list = rules
        return engine
    }

    private func send(_ code: UInt16, type: CGEventType, flags: UInt64 = 0,
                      repeatKey: Bool = false, to engine: MyEngine) throws -> CGEvent? {
        let event = try #require(CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState),
                                        virtualKey: code, keyDown: type != .keyUp))
        event.type = type
        event.flags = CGEventFlags(rawValue: flags)
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
        return engine.handleEvent(proxy: nil, type: type, event: event)?.takeUnretainedValue()
    }

    @Test
    func whitelistBlocksPressRepeatAndReleaseOnlyInSelectedApp() throws {
        let context = Context()
        let engine = engine([block()], context: context)
        defer { ModifierSideTracker.shared.reset() }
        #expect(try send(50, type: .keyDown, to: engine) == nil)
        #expect(try send(50, type: .keyDown, repeatKey: true, to: engine) == nil)
        #expect(try send(50, type: .keyUp, to: engine) == nil)
        #expect(try send(8, type: .keyDown, to: engine) != nil)
        #expect(try send(8, type: .keyUp, to: engine) != nil)
        context.app = "test.other"
        #expect(try send(50, type: .keyDown, to: engine) != nil)
        #expect(try send(50, type: .keyDown, repeatKey: true, to: engine) != nil)
        #expect(try send(50, type: .keyUp, to: engine) != nil)
        #expect(context.posted.isEmpty)
    }

    @Test(arguments: 0..<5)
    func excludedBlockingRulesPassOriginalKeyThrough(scenario: Int) throws {
        let context = Context()
        var rule = block()
        switch scenario {
        case 0: rule.isOn = false
        case 1: rule.appWhitelist = []
        default: break
        }
        let engine = engine([rule], context: context)
        defer { ModifierSideTracker.shared.reset() }
        switch scenario {
        case 2: engine.isPaused = true
        case 3: engine.isRecording = true
        case 4: engine.blacklist = [context.app]
        default: break
        }
        #expect(try send(50, type: .keyDown, to: engine) != nil)
        #expect(try send(50, type: .keyUp, to: engine) != nil)
        #expect(context.posted.isEmpty)
    }

    @Test
    func blacklistModeBlocksEverywhereExceptExcludedApps() throws {
        let context = Context()
        var rule = block()
        rule.appFilterMode = .blacklist
        rule.appBlacklist = ["test.other"]
        let engine = engine([rule], context: context)
        defer { ModifierSideTracker.shared.reset() }
        #expect(try send(50, type: .keyDown, to: engine) == nil)
        #expect(try send(50, type: .keyUp, to: engine) == nil)
        context.app = "test.other"
        #expect(try send(50, type: .keyDown, to: engine) != nil)
        #expect(try send(50, type: .keyUp, to: engine) != nil)
        #expect(context.posted.isEmpty)
    }

    @Test(arguments: 0..<4)
    func heldBlockedKeyFinishesWithoutOutputAfterContextChanges(scenario: Int) throws {
        let context = Context()
        let engine = engine([block()], context: context)
        defer { ModifierSideTracker.shared.reset() }
        #expect(try send(50, type: .keyDown, to: engine) == nil)
        switch scenario {
        case 0: context.app = "test.other"
        case 1: engine.isPaused = true
        case 2: engine.list.removeAll()
        default: engine.stop()
        }
        #expect(try send(50, type: .keyDown, repeatKey: true, to: engine) == nil)
        #expect(try send(50, type: .keyUp, to: engine) == nil)
        // stop 后真实 tap 已不存在；这里只验证已吞掉的按住序列完成清理。
        if scenario != 3 {
            #expect(try send(50, type: .keyDown, to: engine) != nil)
        }
        #expect(context.posted.isEmpty)
    }

    @Test
    func blockingAChordPreservesHeldModifiersForOtherKeys() throws {
        let context = Context()
        let flags = ModifierKey.command.flagValue | UInt64(0x8)
        let engine = engine([block(50, flags: ModifierKey.command.flagValue)], context: context)
        defer { ModifierSideTracker.shared.reset() }
        #expect(try send(55, type: .flagsChanged, flags: flags, to: engine) != nil)
        #expect(try send(50, type: .keyDown, flags: flags, to: engine) == nil)
        let other = try #require(try send(8, type: .keyDown, flags: flags, to: engine))
        #expect(other.flags.rawValue == flags)
        #expect(try send(8, type: .keyUp, flags: flags, to: engine) != nil)
        #expect(try send(50, type: .keyUp, flags: flags, to: engine) == nil)
        #expect(try send(55, type: .flagsChanged, to: engine) != nil)
        #expect(context.posted.isEmpty)
    }

    @Test(arguments: [UInt16(56), 59, 58, 55])
    func modifierCanBeBlockedWithoutSendingAReplacement(code: UInt16) throws {
        let context = Context()
        let engine = engine([block(code)], context: context)
        defer { ModifierSideTracker.shared.reset() }
        let flags = try #require(PhysicalModifierKey.modifier(for: code)?.modifier.flagValue)
        #expect(try send(code, type: .flagsChanged, flags: flags, to: engine) == nil)
        let other = try #require(try send(8, type: .keyDown, flags: flags, to: engine))
        #expect(other.flags.rawValue & ModifierKey.allMask == 0)
        #expect(try send(code, type: .flagsChanged, to: engine) == nil)
        #expect(context.posted.isEmpty)
    }

    @Test
    func disabledChoiceInRadialWheelSendsNoReplacement() throws {
        _ = NSApplication.shared
        let context = Context()
        let engine = engine([block(), MyMap(fCode: 50, fFlags: 0, tCode: 1, tFlags: 0)], context: context)
        defer { engine.stop(); ModifierSideTracker.shared.reset() }
        #expect(try send(50, type: .keyDown, to: engine) == nil)
        #expect(try send(50, type: .keyUp, to: engine) == nil)
        #expect(context.posted.isEmpty)
    }

    @Test
    func blockActionSurvivesStorageExportAndBackup() throws {
        let rule = block()
        let stored = try JSONDecoder().decode(MyMap.self, from: JSONEncoder().encode(rule))
        #expect(stored.action == .block)
        #expect(stored.outputKeyCode == nil)
        #expect(stored.outputModifierCodes.isEmpty)
        #expect(!stored.showsUsageHint)
        let configuration = MappingStore.makeConfiguration(mappings: [rule], blacklist: [], pauseHotkey: MappingStore.defaultPauseHotkey)
        let data = try MappingStore.encodeValidatedConfiguration(configuration)
        let imported = try MappingStore.decodeAndValidateConfiguration(from: data)
        #expect(imported.mappings.first?.action == .block)
        #expect(imported.mappings.first?.appWhitelist == ["test.xmind"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let backup = try BackupManager.writeBackup(.init(configuration: configuration, directory: directory, maximumBackupCount: 5))
        let restored = try MappingStore.decodeAndValidateConfiguration(at: backup.url)
        #expect(restored.mappings.first?.action == .block)
    }

    @Test(arguments: ["2.0", "3.0", "4.0"])
    func olderConfigurationsDefaultToRemapping(version: String) throws {
        let configuration = MappingStore.makeConfiguration(mappings: [MyMap(fCode: 50, fFlags: 0, tCode: 1, tFlags: 0)], blacklist: [], pauseHotkey: MappingStore.defaultPauseHotkey)
        var document = try #require(JSONSerialization.jsonObject(with: MappingStore.encodeConfiguration(configuration)) as? [String: Any])
        document["version"] = version
        var rules = try #require(document["mappings"] as? [[String: Any]])
        rules[0].removeValue(forKey: "action")
        document["mappings"] = rules
        let decoded = try MappingStore.decodeAndValidateConfiguration(from: JSONSerialization.data(withJSONObject: document))
        #expect(decoded.mappings.first?.action == .remap)
        #expect(decoded.mappings.first?.outputKeyCode == 1)
        let stored = try JSONDecoder().decode(MyMap.self, from: JSONSerialization.data(withJSONObject: rules[0]))
        #expect(stored.action == .remap)
    }

    @Test
    func unknownActionIsRejectedDuringImport() throws {
        let configuration = MappingStore.makeConfiguration(mappings: [block()], blacklist: [], pauseHotkey: MappingStore.defaultPauseHotkey)
        var document = try #require(JSONSerialization.jsonObject(with: MappingStore.encodeConfiguration(configuration)) as? [String: Any])
        var rules = try #require(document["mappings"] as? [[String: Any]])
        rules[0]["action"] = "unknown"
        document["mappings"] = rules
        #expect(throws: MappingStore.ConfigurationError.self) {
            try MappingStore.decodeAndValidateConfiguration(from: JSONSerialization.data(withJSONObject: document))
        }
    }
}
