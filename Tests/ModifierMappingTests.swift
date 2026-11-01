import Foundation
import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import KeyMapperCore

@Suite @MainActor
struct ModifierMappingTests {
    @Test
    func sortingKeepsCreationOrderAndEnabledGroupsStable() {
        let olderSaved = MyMap(fCode: 0, fFlags: 0, tCode: 1, tFlags: 0, isOn: false, createdAt: nil)
        let newer = MyMap(fCode: 2, fFlags: 0, tCode: 3, tFlags: 0, createdAt: Date(timeIntervalSince1970: 2000))
        let newerSaved = MyMap(fCode: 4, fFlags: 0, tCode: 5, tFlags: 0, createdAt: nil)
        let datedOlder = MyMap(fCode: 6, fFlags: 0, tCode: 7, tFlags: 0, isOn: false, createdAt: Date(timeIntervalSince1970: 1000))
        let sameTimestamp = MyMap(fCode: 8, fFlags: 0, tCode: 9, tFlags: 0, isOn: false, createdAt: newer.createdAt)
        let rules = [olderSaved, newer, newerSaved, datedOlder, sameTimestamp]
        #expect(RuleSortOrder.oldestFirst.sorted(rules).map(\.id) == [olderSaved.id, newerSaved.id, datedOlder.id, newer.id, sameTimestamp.id])
        #expect(RuleSortOrder.newestFirst.sorted(rules).map(\.id) == [sameTimestamp.id, newer.id, datedOlder.id, newerSaved.id, olderSaved.id])
        #expect(RuleSortOrder.enabledFirst.sorted(rules).map(\.id) == [newer.id, newerSaved.id, sameTimestamp.id, datedOlder.id, olderSaved.id])
    }

    @Test
    func creationDatesSurviveConfigurationAndOldRulesWithoutDatesImport() throws {
        let date = Date(timeIntervalSince1970: 1000)
        let shortcut = MyMap(fCode: 0, fFlags: 0, tCode: 1, tFlags: 0, createdAt: date)
        let modifier = ModifierMapping(source: .control, target: .command, createdAt: date)
        #expect(modifier.rule.createdAt == date)
        let configuration = MappingStore.makeConfiguration(
            mappings: [shortcut], modifierMappings: [modifier], blacklist: [], pauseHotkey: MappingStore.defaultPauseHotkey
        )
        let data = try MappingStore.encodeValidatedConfiguration(configuration)
        let decoded = try MappingStore.decodeAndValidateConfiguration(from: data)
        #expect(decoded.mappings[0].createdAt == date)
        #expect(decoded.modifierMappings[0].createdAt == date)

        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var records = try #require(json["mappings"] as? [[String: Any]])
        var modifiers = try #require(json["modifierMappings"] as? [[String: Any]])
        records[0].removeValue(forKey: "createdAt")
        modifiers[0].removeValue(forKey: "createdAt")
        json["mappings"] = records
        json["modifierMappings"] = modifiers
        let legacy = try MappingStore.decodeAndValidateConfiguration(from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.mappings[0].createdAt == nil)
        #expect(legacy.modifierMappings[0].createdAt == nil)
        let saved = try JSONDecoder().decode(MyMap.self, from: JSONSerialization.data(withJSONObject: records[0]))
        #expect(saved.createdAt == nil)
    }

    private let swap = [
        ModifierMapping(source: .control, target: .command),
        ModifierMapping(source: .command, target: .control)
    ]

    private struct SentEvent {
        let type: CGEventType
        let code: UInt16
        let flags: UInt64
    }

    private final class EventLog {
        var events: [SentEvent] = []
        var frontmostApp = "test.target"

        func capture(_ event: CGEvent) {
            events.append(SentEvent(type: event.type, code: UInt16(event.getIntegerValueField(.keyboardEventKeycode)), flags: event.flags.rawValue))
        }
    }

    private func engine(rules: [MyMap], log: EventLog) -> MyEngine {
        ModifierSideTracker.shared.reset()
        let engine = MyEngine(startMonitoring: false, eventPoster: { event, _ in log.capture(event) }, frontmostBundleID: { log.frontmostApp })
        engine.list = rules
        return engine
    }

    private func send(_ code: UInt16, type: CGEventType, flags: UInt64, to engine: MyEngine, log: EventLog) throws {
        let event = try #require(CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: code, keyDown: type != .keyUp))
        event.type = type
        event.flags = CGEventFlags(rawValue: flags)
        if let returned = engine.handleEvent(proxy: nil, type: type, event: event) {
            log.capture(returned.takeUnretainedValue())
        }
    }

    @Test
    func optionToCommandVPairsTargetEventsAndSuppressesOption() throws {
        let log = EventLog()
        let mapping = MyMap(fCode: 58, fFlags: 0, tCode: 9, tFlags: ModifierKey.command.flagValue)
        let engine = engine(rules: [mapping], log: log)
        defer { ModifierSideTracker.shared.reset() }
        try send(58, type: .flagsChanged, flags: ModifierKey.option.flagValue, to: engine, log: log)
        try send(58, type: .flagsChanged, flags: 0, to: engine, log: log)
        #expect(log.events.map(\.code) == [55, 9, 9, 55])
        #expect(log.events.map(\.type) == [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        #expect((log.events[1].flags & ModifierKey.allMask) == ModifierKey.command.flagValue)
        #expect((log.events.last!.flags & ModifierKey.allMask) == 0)
    }

    @Test
    func ordinaryKeyCanHoldAModifierForFollowingKeys() throws {
        let log = EventLog()
        let engine = engine(rules: [MyMap(fCode: 0, fFlags: 0, tCode: 59, tFlags: 0)], log: log)
        defer { ModifierSideTracker.shared.reset() }
        try send(0, type: .keyDown, flags: 0, to: engine, log: log)
        try send(8, type: .keyDown, flags: 0, to: engine, log: log)
        try send(8, type: .keyUp, flags: 0, to: engine, log: log)
        try send(0, type: .keyUp, flags: 0, to: engine, log: log)
        #expect(log.events.map(\.code) == [59, 8, 8, 59])
        #expect((log.events[1].flags & ModifierKey.allMask) == ModifierKey.control.flagValue)
        #expect((log.events.last!.flags & ModifierKey.allMask) == 0)
    }

    @Test
    func unifiedModifierSwapsRemainActiveAcrossAppChanges() throws {
        let log = EventLog()
        let engine = engine(rules: [
            MyMap(fCode: 59, fFlags: 0, tCode: 55, tFlags: 0),
            MyMap(fCode: 55, fFlags: 0, tCode: 59, tFlags: 0)
        ], log: log)
        defer { ModifierSideTracker.shared.reset() }
        try send(59, type: .flagsChanged, flags: ModifierKey.control.flagValue, to: engine, log: log)
        log.frontmostApp = "test.other"
        try send(8, type: .keyDown, flags: ModifierKey.control.flagValue, to: engine, log: log)
        try send(8, type: .keyUp, flags: ModifierKey.control.flagValue, to: engine, log: log)
        try send(59, type: .flagsChanged, flags: 0, to: engine, log: log)
        #expect(log.events.map(\.code) == [55, 8, 8, 55])
        #expect((log.events[1].flags & ModifierKey.allMask) == ModifierKey.command.flagValue)
    }

    @Test
    func pausingAModifierActionReleasesTheTargetBeforeRestoringTheSource() throws {
        let log = EventLog()
        let engine = engine(rules: [MyMap(fCode: 58, fFlags: 0, tCode: 9, tFlags: ModifierKey.command.flagValue)], log: log)
        defer { ModifierSideTracker.shared.reset() }
        try send(58, type: .flagsChanged, flags: ModifierKey.option.flagValue, to: engine, log: log)
        engine.isPaused = true
        #expect(log.events.filter { $0.type == .keyUp && $0.code == 9 }.count == 1)
        #expect((log.events.last!.flags & ModifierKey.allMask) == ModifierKey.option.flagValue)
        try send(58, type: .flagsChanged, flags: 0, to: engine, log: log)
        #expect((log.events.last!.flags & ModifierKey.allMask) == 0)
    }

    @Test
    func appChangesFinishModifierActionsWithoutLeakingTargetModifiers() throws {
        let log = EventLog()
        let engine = engine(rules: [MyMap(fCode: 58, fFlags: 0, tCode: 9, tFlags: ModifierKey.command.flagValue)], log: log)
        defer { ModifierSideTracker.shared.reset() }
        try send(58, type: .flagsChanged, flags: ModifierKey.option.flagValue, to: engine, log: log)
        log.frontmostApp = "test.other"
        try send(11, type: .keyDown, flags: ModifierKey.option.flagValue, to: engine, log: log)
        #expect(log.events.filter { $0.type == .keyUp && $0.code == 9 }.count == 1)
        #expect(log.events.last?.code == 11)
        #expect((log.events.last!.flags & ModifierKey.allMask) == ModifierKey.option.flagValue)
        try send(58, type: .flagsChanged, flags: 0, to: engine, log: log)
        #expect((log.events.last!.flags & ModifierKey.allMask) == 0)
    }

    @Test
    func flexibleRulesAndDismissedTipsRoundTripThroughConfiguration() throws {
        var mapping = MyMap(fCode: 58, fFlags: 0, tCode: 9, tFlags: ModifierKey.command.flagValue)
        #expect(mapping.showsUsageHint)
        mapping.hasDismissedUsageHint = true
        #expect(!mapping.showsUsageHint)
        let reverse = MyMap(fCode: 9, fFlags: ModifierKey.command.flagValue, tCode: 58, tFlags: 0)
        #expect(reverse.showsUsageHint)
        let configuration = MappingStore.makeConfiguration(mappings: [mapping, reverse], blacklist: [], pauseHotkey: MappingStore.defaultPauseHotkey)
        let data = try MappingStore.encodeValidatedConfiguration(configuration)
        let decoded = try MappingStore.decodeAndValidateConfiguration(from: data)
        #expect(decoded.mappings.count == 2)
        #expect(decoded.mappings[0].hasDismissedUsageHint)
        #expect(!decoded.mappings[0].showsUsageHint)
        #expect(decoded.mappings[1].targetModifier == .option)
        #expect(decoded.mappings[1].showsUsageHint)
        #expect(!MyMap(fCode: 59, fFlags: 0, tCode: 55, tFlags: 0).showsUsageHint)
        #expect(!MappingStore.defaultMappings()[0].showsUsageHint)
    }

    private final class RecordingValues {
        var isRecording = true
        var selection: (UInt16, UInt64)?
    }

    private func recorder(allowsModifierOnly: Bool) -> (KV, RecordingValues) {
        ModifierSideTracker.shared.reset()
        let values = RecordingValues()
        let coordinator = KeyLogic.Coordinator(
            r1: Binding(get: { values.isRecording }, set: { values.isRecording = $0 }),
            r2: .constant(false),
            t1: Binding(get: { values.selection }, set: { values.selection = $0 }),
            t2: .constant(nil), s1: .constant(.any), s2: .constant(.any),
            allowsModifierOnly: allowsModifierOnly
        )
        return (KV(coordinator: coordinator), values)
    }

    private func keyEvent(_ code: UInt16, type: CGEventType, flags: UInt64) throws -> NSEvent {
        let source = CGEventSource(stateID: .privateState)
        let event = try #require(CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: type != .keyUp))
        event.type = type
        event.flags = CGEventFlags(rawValue: flags)
        return try #require(NSEvent(cgEvent: event))
    }

    @Test
    func recorderAcceptsSingleModifiersOnTheOriginalRecordingField() throws {
        let (view, values) = recorder(allowsModifierOnly: true)
        defer { ModifierSideTracker.shared.reset() }
        view.prepareRecording()
        view.flagsChanged(with: try keyEvent(59, type: .flagsChanged, flags: ModifierKey.control.flagValue))
        #expect(values.isRecording)
        #expect(values.selection == nil)
        view.flagsChanged(with: try keyEvent(59, type: .flagsChanged, flags: 0))
        #expect(!values.isRecording)
        #expect(values.selection?.0 == 59)
        #expect(values.selection?.1 == 0)
    }

    @Test
    func recorderStillCapturesCtrlCAsACompleteShortcut() throws {
        let (view, values) = recorder(allowsModifierOnly: true)
        defer { ModifierSideTracker.shared.reset() }
        view.prepareRecording()
        view.flagsChanged(with: try keyEvent(59, type: .flagsChanged, flags: ModifierKey.control.flagValue))
        #expect(values.isRecording)
        view.keyDown(with: try keyEvent(8, type: .keyDown, flags: ModifierKey.control.flagValue))
        #expect(!values.isRecording)
        #expect(values.selection?.0 == 8)
        #expect(values.selection?.1 == ModifierKey.control.flagValue)
    }

    @Test
    func pauseHotkeyRecorderKeepsRequiringAnOrdinaryKey() throws {
        let (view, values) = recorder(allowsModifierOnly: false)
        defer { ModifierSideTracker.shared.reset() }
        view.prepareRecording()
        view.flagsChanged(with: try keyEvent(59, type: .flagsChanged, flags: ModifierKey.control.flagValue))
        view.flagsChanged(with: try keyEvent(59, type: .flagsChanged, flags: 0))
        #expect(values.isRecording)
        #expect(values.selection == nil)
        view.keyDown(with: try keyEvent(6, type: .keyDown, flags: 0))
        #expect(!values.isRecording)
        #expect(values.selection?.0 == 6)
    }

    @Test
    func recorderHandlesAnEventAlreadyTrackedByTheEventTap() throws {
        let (view, values) = recorder(allowsModifierOnly: true)
        defer { ModifierSideTracker.shared.reset() }
        // The event tap may receive this before SwiftUI updates the recording NSView.
        ModifierSideTracker.shared.updateFlagsChanged(keyCode: 59, flags: ModifierKey.control.flagValue)
        view.flagsChanged(with: try keyEvent(59, type: .flagsChanged, flags: ModifierKey.control.flagValue))
        view.flagsChanged(with: try keyEvent(59, type: .flagsChanged, flags: 0))
        #expect(values.selection?.0 == 59)
        #expect(values.selection?.1 == 0)
    }

    @Test(arguments: [UInt16(54), 55, 56, 58, 59, 60, 61, 62])
    func singleModifierRecordsOnlyAfterRelease(code: UInt16) {
        var recording = ModifierKeyRecording()
        #expect(recording.update(keyCode: code, isDown: true) == nil)
        #expect(recording.update(keyCode: code, isDown: true) == nil)
        #expect(recording.update(keyCode: code, isDown: false) == code)
        #expect(recording.update(keyCode: code, isDown: false) == nil)
    }

    @Test
    func modifierChordsAndCancelledRecordingsDoNotBecomeSingleKeys() {
        var recording = ModifierKeyRecording()
        #expect(recording.update(keyCode: 59, isDown: true) == nil)
        #expect(recording.update(keyCode: 56, isDown: true) == nil)
        #expect(recording.update(keyCode: 56, isDown: false) == nil)
        #expect(recording.update(keyCode: 59, isDown: false) == nil)
        #expect(recording.update(keyCode: 59, isDown: true) == nil)
        #expect(recording.update(keyCode: 59, isDown: false) == 59)
        _ = recording.update(keyCode: 59, isDown: true)
        // An ordinary keyDown commits Ctrl+C, or focus loss cancels the recording.
        recording.begin()
        #expect(recording.update(keyCode: 59, isDown: false) == nil)
        recording.begin(held: [55])
        #expect(recording.update(keyCode: 55, isDown: false) == nil)
    }

    @Test
    func sharedRuleCardsKeepModifierNamesNotesAndExclusions() {
        let mapping = ModifierMapping(source: .control, target: .command, note: "remote", appBlacklist: ["test.app"])
        let rule = mapping.rule
        #expect(rule.id == mapping.id)
        #expect(ModifierMapping.modifier(in: (rule.fCode, rule.fFlags)) == .control)
        #expect(ModifierMapping.modifier(in: (rule.tCode, rule.tFlags)) == .command)
        #expect(MyMap.getName(rule.fCode, rule.fFlags) == "⌃ Control")
        #expect(rule.note == "remote")
        #expect(rule.appBlacklist == ["test.app"])
        #expect(ModifierMapping.modifier(in: (8, ModifierKey.control.flagValue)) == nil)
    }

    @Test
    func existingModifierConfigsWithoutNotesStillImport() throws {
        var json = try #require(JSONSerialization.jsonObject(with: configurationData()) as? [String: Any])
        var rules = try #require(json["modifierMappings"] as? [[String: Any]])
        for index in rules.indices { rules[index].removeValue(forKey: "note") }
        json["modifierMappings"] = rules
        let decoded = try MappingStore.decodeAndValidateConfiguration(from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.modifierMappings.count == 2)
        #expect(decoded.modifierMappings.allSatisfy { $0.note.isEmpty })
    }

    @Test
    func sharedListRejectsCollidingIDsAcrossRuleTypes() throws {
        var json = try #require(JSONSerialization.jsonObject(with: configurationData()) as? [String: Any])
        var rules = try #require(json["modifierMappings"] as? [[String: Any]])
        let shortcuts = try #require(json["mappings"] as? [[String: Any]])
        rules[0]["id"] = shortcuts[0]["id"]
        json["modifierMappings"] = rules
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: MappingStore.ConfigurationError.self) {
            try MappingStore.decodeAndValidateConfiguration(from: data)
        }
    }

    private func mapped(_ codes: Set<UInt16>, rules: [ModifierMapping]? = nil,
                        app: String? = "test.app", enabled: Bool = true) -> Set<UInt16> {
        ModifierRemappingState.mappedCodes(codes, rules: rules ?? swap, bundleID: app, enabled: enabled)
    }

    @Test(arguments: 0..<256)
    func swapPreservesEveryPhysicalChord(mask: Int) {
        let physical: [UInt16] = [59, 62, 55, 54, 58, 61, 56, 60]
        let swapped: [UInt16] = [55, 54, 59, 62, 58, 61, 56, 60]
        let held = Set(physical.indices.filter { mask & (1 << $0) != 0 }.map { physical[$0] })
        let expected = Set(swapped.indices.filter { mask & (1 << $0) != 0 }.map { swapped[$0] })
        #expect(mapped(held) == expected)
        #expect(mapped(mapped(held)) == held)
    }

    @Test
    func allFourModifiersPreserveTheirPhysicalSide() {
        for source in ModifierKey.allCases {
            for target in ModifierKey.allCases where source != target {
                let rule = ModifierMapping(source: source, target: target)
                for side in [ModifierSide.left, .right] {
                    let input = PhysicalModifierKey.keyCode(for: source, side: side)
                    let output = PhysicalModifierKey.keyCode(for: target, side: side)
                    #expect(mapped([input], rules: [rule]) == [output])
                }
            }
        }
    }

    @Test
    func sharedTargetStaysDownUntilBothSourcesRelease() {
        let rules = [ModifierMapping(source: .control, target: .command)]
        var state = ModifierRemappingState()
        var changes = state.transition(to: mapped([59], rules: rules))
        #expect(changes.map(\.keyCode) == [55])
        #expect(changes.allSatisfy { $0.isDown })
        // The physical Command key shares the same logical left Command.
        #expect(state.transition(to: mapped([59, 55], rules: rules)).isEmpty)
        #expect(state.transition(to: mapped([55], rules: rules)).isEmpty)
        changes = state.transition(to: mapped([], rules: rules))
        #expect(changes.map(\.keyCode) == [55])
        #expect(changes.allSatisfy { !$0.isDown })
        #expect(changes.last?.flags == 0)
    }

    @Test
    func releasingOneSideDoesNotReleaseTheOtherSide() throws {
        var state = ModifierRemappingState()
        _ = state.transition(to: mapped([59, 62]))
        let changes = state.transition(to: mapped([62]))
        #expect(changes.count == 1)
        #expect(changes.first?.keyCode == 55)
        #expect(changes.first?.isDown == false)
        let change = try #require(changes.first)
        #expect((change.flags & ModifierKey.command.flagValue) != 0)
        #expect(state.outputCodes == [54])
    }

    @Test
    func pauseRecordingAppChangesAndRuleRemovalRestorePhysicalKeys() {
        var state = ModifierRemappingState()
        _ = state.transition(to: mapped([59]))
        let paused = state.transition(to: mapped([59], enabled: false))
        #expect(paused.map(\.keyCode) == [55, 59])
        #expect(paused.map(\.isDown) == [false, true])
        #expect(state.outputCodes == [59])
        _ = state.transition(to: mapped([59]))
        #expect(state.outputCodes == [55])

        var blocked = swap
        blocked[0].appBlacklist = ["remote.app"]
        _ = state.transition(to: mapped([59], rules: blocked, app: "remote.app"))
        #expect(state.outputCodes == [59])
        _ = state.transition(to: mapped([59], rules: blocked, app: "other.app"))
        #expect(state.outputCodes == [55])
        _ = state.transition(to: mapped([59], rules: []))
        #expect(state.outputCodes == [59])
        let release = state.transition(to: [])
        #expect(release.count == 1)
        #expect(release.first?.keyCode == 59)
        #expect(release.first?.isDown == false)
    }

    @Test
    func disabledRulesAndUnknownApps() {
        var disabled = swap
        disabled[0].isOn = false
        #expect(mapped([59], rules: disabled) == [59])
        #expect(mapped([59], app: nil) == [55])
    }

    @Test
    func keyboardAndMouseFlagsKeepCapsLockFnAndOtherFlags() {
        let otherFlags: UInt64 = 0x10000 | 0x200000 | 0x800000 | 0x100
        let physical = otherFlags | ModifierKey.control.flagValue | 0x1
        let output = ModifierRemappingState.flags(for: mapped([59]), preserving: physical)
        #expect(output == otherFlags | ModifierKey.command.flagValue | 0x8)
        let right = ModifierRemappingState.flags(for: [54], preserving: physical)
        #expect(right == otherFlags | ModifierKey.command.flagValue | 0x10)
    }

    @Test
    func shortcutTargetsOverrideRemappedSourcesWithoutCascading() {
        // Physical Ctrl becomes Command; a matching Ctrl+C → Option+C rule takes priority.
        let result = ModifierRemappingState.applyingShortcuts(
            to: mapped([59]), overrides: [(source: mapped([59]), target: [58])]
        )
        #expect(result == [58])
        // One active shortcut's source must not remove another shortcut's target.
        let overlapping = ModifierRemappingState.applyingShortcuts(
            to: [55, 58], overrides: [(source: [55], target: [58]), (source: [58], target: [56])]
        )
        #expect(overlapping == [58, 56])
    }

    private func configurationData(rules: [ModifierMapping]? = nil) throws -> Data {
        let configuration = MappingStore.makeConfiguration(
            mappings: MappingStore.defaultMappings(), modifierMappings: rules ?? swap,
            blacklist: ["global.blocked"], pauseHotkey: MappingStore.defaultPauseHotkey
        )
        return try MappingStore.encodeValidatedConfiguration(configuration)
    }

    @Test
    func versionThreeRoundTripIncludesBothRuleTypes() throws {
        var rules = swap
        rules[0].appBlacklist = ["remote.app"]
        let data = try configurationData(rules: rules)
        let document = try JSONDecoder().decode(MappingStore.Configuration.self, from: data)
        #expect(document.version == "3.0")
        let decoded = try MappingStore.decodeAndValidateConfiguration(from: data)
        #expect(decoded.modifierMappings == rules)
        #expect(decoded.mappings.count == MappingStore.defaultMappings().count)
        #expect(decoded.mappings.first?.appBlacklist == ["com.apple.Terminal"])
        #expect(decoded.blacklist == ["global.blocked"])
        #expect(decoded.pauseHotkey.flags == MappingStore.defaultPauseHotkey.flags)
    }

    @Test
    func versionTwoWithoutModifierRulesStillImports() throws {
        var json = try #require(JSONSerialization.jsonObject(with: configurationData()) as? [String: Any])
        json["version"] = "2.0"
        json.removeValue(forKey: "modifierMappings")
        let decoded = try MappingStore.decodeAndValidateConfiguration(from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.modifierMappings.isEmpty)
        #expect(decoded.mappings.count == 6)
    }

    @Test(arguments: 0..<7)
    func invalidModifierRulesAreRejected(scenario: Int) throws {
        var json = try #require(JSONSerialization.jsonObject(with: configurationData()) as? [String: Any])
        var rules = try #require(json["modifierMappings"] as? [[String: Any]])
        switch scenario {
        case 0: rules[1]["source"] = rules[0]["source"]
        case 1: rules[1]["id"] = rules[0]["id"]
        case 2: rules[0]["target"] = rules[0]["source"]
        case 3: rules[0]["appBlacklist"] = [" remote.app"]
        case 4: rules[0]["source"] = "capsLock"
        case 5: rules.append(contentsOf: rules + [rules[0]])
        default: json.removeValue(forKey: "modifierMappings")
        }
        if scenario != 6 { json["modifierMappings"] = rules }
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: MappingStore.ConfigurationError.self) {
            try MappingStore.decodeAndValidateConfiguration(from: data)
        }
    }

    @Test
    func shortcutRecordsStillRejectModifierOnlyKeyCodes() throws {
        var json = try #require(JSONSerialization.jsonObject(with: configurationData()) as? [String: Any])
        var records = try #require(json["mappings"] as? [[String: Any]])
        records[0]["fCode"] = 59
        json["mappings"] = records
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: MappingStore.ConfigurationError.self) {
            try MappingStore.decodeAndValidateConfiguration(from: data)
        }
    }
}
