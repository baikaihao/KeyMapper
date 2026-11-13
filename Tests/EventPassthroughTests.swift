import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import KeyMapperCore

@Suite @MainActor
struct EventPassthroughTests {
    enum Context: CaseIterable {
        case noRules, disabledRules, paused, globalBlacklist, ruleBlacklist, outsideWhitelist, recording
    }

    private final class EventLog {
        var posted: [CGEvent] = []
        var bundleID = "test.target"
    }

    private func engine(context: Context, log: EventLog) -> MyEngine {
        ModifierSideTracker.shared.reset()
        let engine = MyEngine(startMonitoring: false, eventPoster: { event, _ in
            log.posted.append(event)
        }, frontmostBundleID: { log.bundleID })
        if context != .noRules {
            engine.list = [MyMap(fCode: 56, fFlags: 0, tCode: 55, tFlags: 0,
                                 isOn: context != .disabledRules)]
            // 旧格式的修饰键规则也必须受暂停和全局黑名单约束。
            engine.modifierMappings = [ModifierMapping(source: .control, target: .command,
                                                       isOn: context != .disabledRules)]
        }
        switch context {
        case .paused: engine.isPaused = true
        case .globalBlacklist: engine.blacklist = [log.bundleID]
        case .ruleBlacklist:
            engine.list[0].appBlacklist = [log.bundleID]
            engine.modifierMappings[0].appBlacklist = [log.bundleID]
        case .outsideWhitelist:
            engine.list[0].appFilterMode = .whitelist
            engine.modifierMappings[0].appFilterMode = .whitelist
        case .recording: engine.isRecording = true
        case .noRules, .disabledRules: break
        }
        return engine
    }

    private func event(_ code: UInt16, type: CGEventType, flags: UInt64) throws -> CGEvent {
        let event = try #require(CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState),
                                        virtualKey: code, keyDown: type != .keyUp))
        event.type = type
        event.flags = CGEventFlags(rawValue: flags)
        event.timestamp = 123_456_789
        event.setIntegerValueField(.eventSourceUserData, value: 987_654)
        return event
    }

    private func expectUnchanged(_ event: CGEvent, engine: MyEngine, log: EventLog) throws {
        let flags = event.flags
        let originalData = try #require(event.data) as Data
        let count = log.posted.count
        let returned = try #require(engine.handleEvent(proxy: nil, type: event.type, event: event))
        #expect(returned.takeUnretainedValue() === event)
        #expect(event.flags == flags)
        #expect(try #require(event.data) as Data == originalData)
        #expect(log.posted.count == count)
    }

    @Test(arguments: Context.allCases, [UInt16(56), 60, 59, 62, 58, 61, 55, 54])
    func excludedModifierGesturesKeepOriginalEvents(context: Context, code: UInt16) throws {
        let log = EventLog()
        let engine = engine(context: context, log: log)
        defer { ModifierSideTracker.shared.reset() }
        let modifier = try #require(PhysicalModifierKey.modifier(for: code)?.modifier)
        let flags = modifier.flagValue | CGEventFlags.maskNonCoalesced.rawValue
        try expectUnchanged(event(code, type: .flagsChanged, flags: flags), engine: engine, log: log)
        #expect(ModifierSideTracker.shared.heldKeyCodes == [code])
        // 重复的 flagsChanged 也要原样透传，不能因状态没有变化而吞掉。
        try expectUnchanged(event(code, type: .flagsChanged, flags: flags), engine: engine, log: log)
        try expectUnchanged(event(0, type: .keyDown, flags: flags), engine: engine, log: log)
        try expectUnchanged(event(0, type: .keyUp, flags: flags), engine: engine, log: log)
        try expectUnchanged(event(0, type: .scrollWheel, flags: flags), engine: engine, log: log)
        try expectUnchanged(event(code, type: .flagsChanged, flags: 0), engine: engine, log: log)
        #expect(ModifierSideTracker.shared.heldKeyCodes.isEmpty)
    }

    @Test(arguments: Context.allCases, [UInt16(57), 63])
    func capsLockAndFnKeepOriginalEvents(context: Context, code: UInt16) throws {
        let log = EventLog()
        let engine = engine(context: context, log: log)
        defer { ModifierSideTracker.shared.reset() }
        let flags = code == 57 ? CGEventFlags.maskAlphaShift.rawValue : CGEventFlags.maskSecondaryFn.rawValue
        try expectUnchanged(event(code, type: .flagsChanged, flags: flags), engine: engine, log: log)
        try expectUnchanged(event(code, type: .flagsChanged, flags: 0), engine: engine, log: log)
    }

    @Test
    func unrelatedShiftGestureKeepsOriginalEventsWithActiveControlMapping() throws {
        let log = EventLog()
        let engine = engine(context: .noRules, log: log)
        engine.list = [MyMap(fCode: 59, fFlags: 0, tCode: 55, tFlags: 0)]
        defer { ModifierSideTracker.shared.reset() }
        try expectUnchanged(event(56, type: .flagsChanged, flags: ModifierKey.shift.flagValue), engine: engine, log: log)
        try expectUnchanged(event(56, type: .flagsChanged, flags: 0), engine: engine, log: log)
    }

    @Test
    func resumingUsesModifiersTrackedDuringPause() throws {
        let log = EventLog()
        let engine = engine(context: .paused, log: log)
        defer { ModifierSideTracker.shared.reset() }
        try expectUnchanged(event(56, type: .flagsChanged, flags: ModifierKey.shift.flagValue), engine: engine, log: log)
        engine.isPaused = false
        #expect(log.posted.map { UInt16($0.getIntegerValueField(.keyboardEventKeycode)) } == [56, 55])
        let release = try event(56, type: .flagsChanged, flags: 0)
        #expect(engine.handleEvent(proxy: nil, type: .flagsChanged, event: release) == nil)
        #expect(log.posted.last?.flags.rawValue == 0)
    }

    @Test
    func enteringBlacklistReleasesMappedModifiersBeforePassingNativeEvents() throws {
        let log = EventLog()
        let engine = engine(context: .noRules, log: log)
        engine.list = [MyMap(fCode: 59, fFlags: 0, tCode: 55, tFlags: 0)]
        engine.blacklist = ["test.blocked"]
        defer { ModifierSideTracker.shared.reset() }
        let press = try event(59, type: .flagsChanged, flags: ModifierKey.control.flagValue)
        #expect(engine.handleEvent(proxy: nil, type: .flagsChanged, event: press) == nil)
        log.bundleID = "test.blocked"
        let key = try event(0, type: .keyDown, flags: ModifierKey.control.flagValue)
        let originalData = try #require(key.data) as Data
        #expect(engine.handleEvent(proxy: nil, type: .keyDown, event: key)?.takeUnretainedValue() === key)
        #expect(try #require(key.data) as Data == originalData)
        #expect(log.posted.map { UInt16($0.getIntegerValueField(.keyboardEventKeycode)) } == [55, 55, 59])
        try expectUnchanged(event(59, type: .flagsChanged, flags: 0), engine: engine, log: log)
        #expect(ModifierSideTracker.shared.heldKeyCodes.isEmpty)
    }

    @Test(arguments: [Context.paused, .globalBlacklist])
    func excludedHeldShortcutsStillReleaseTheirTargets(context: Context) throws {
        let log = EventLog()
        let engine = engine(context: .noRules, log: log)
        engine.list = [MyMap(fCode: 0, fFlags: 0, tCode: 1, tFlags: ModifierKey.command.flagValue)]
        engine.blacklist = ["test.blocked"]
        defer { ModifierSideTracker.shared.reset() }
        let press = try event(0, type: .keyDown, flags: 0)
        #expect(engine.handleEvent(proxy: nil, type: .keyDown, event: press) == nil)
        if context == .paused {
            engine.isPaused = true
        } else {
            log.bundleID = "test.blocked"
        }
        let release = try event(0, type: .keyUp, flags: 0)
        #expect(engine.handleEvent(proxy: nil, type: .keyUp, event: release) == nil)
        #expect(log.posted.filter { $0.getIntegerValueField(.keyboardEventKeycode) == 1 }.map(\.type) == [.keyDown, .keyUp])
        #expect(!log.posted.contains { $0.getIntegerValueField(.keyboardEventKeycode) == 0 })
        #expect(log.posted.last?.flags.rawValue == 0)
        try expectUnchanged(event(56, type: .flagsChanged, flags: ModifierKey.shift.flagValue), engine: engine, log: log)
        try expectUnchanged(event(56, type: .flagsChanged, flags: 0), engine: engine, log: log)
    }

    @Test(arguments: [CGEventType.keyDown, .keyUp, .leftMouseDown, .scrollWheel, .flagsChanged])
    func activeModifierMappingStillRewritesDependentEvents(type: CGEventType) throws {
        let log = EventLog()
        let engine = engine(context: .noRules, log: log)
        engine.list = [MyMap(fCode: 59, fFlags: 0, tCode: 55, tFlags: 0)]
        defer { ModifierSideTracker.shared.reset() }
        let press = try event(59, type: .flagsChanged, flags: ModifierKey.control.flagValue)
        #expect(engine.handleEvent(proxy: nil, type: .flagsChanged, event: press) == nil)
        let physicalFlags = ModifierKey.control.flagValue | CGEventFlags.maskAlphaShift.rawValue
            | CGEventFlags.maskSecondaryFn.rawValue | CGEventFlags.maskNonCoalesced.rawValue
        let dependent = try event(type == .flagsChanged ? 57 : 8, type: type, flags: physicalFlags)
        let returned = try #require(engine.handleEvent(proxy: nil, type: type, event: dependent))
        #expect(returned.takeUnretainedValue() === dependent)
        #expect(dependent.flags.rawValue == ModifierRemappingState.flags(for: [55], preserving: physicalFlags))
        #expect(log.posted.count == 1)
        let release = try event(59, type: .flagsChanged, flags: 0)
        #expect(engine.handleEvent(proxy: nil, type: .flagsChanged, event: release) == nil)
        #expect(log.posted.last?.flags.rawValue == 0)
    }
}
