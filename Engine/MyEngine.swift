import SwiftUI
import Combine
import AppKit

extension Notification.Name {
    static let mappingTriggered = Notification.Name("mappingTriggered")
    static let cancelKeyRecording = Notification.Name("cancelKeyRecording")
}

// MARK: - MyEngine
// 核心键盘事件拦截与映射引擎（单例）。
// 这是整个 KeyMapper 最关键的组件，负责在系统级别拦截键盘事件并进行映射。
//
// 工作流程：
// 1. 使用 CGEvent.tapCreate 在系统级别创建键盘事件监听（keyDown/keyUp）
// 2. 在回调中按优先级依次检查：自身事件 → 录制模式 → 自身应用 → 暂停热键 → 暂停状态 → 规则级黑名单
// 3. 匹配映射规则后，构造新的 CGEvent 发送映射后的按键事件
// 4. 同一按键映射到多个目标时，弹出径向选择轮盘（RadialWheel）
//
// 数据持久化：
// - 映射规则、全局默认黑名单、暂停热键均通过 UserDefaults + JSON 编码持久化

class MyEngine: ObservableObject {
    static let shared = MyEngine()

    // MARK: - 发布属性（UI 绑定）

    private var isApplyingConfiguration = false
    // 映射规则列表，变更时自动持久化
    @Published var list: [MyMap] = [] {
        didSet {
            if !isApplyingConfiguration { MappingStore.shared.saveList(list) }
        }
    }
    @Published var isActive: Bool = false
    @Published var isPaused: Bool = false
    @Published var pauseHotkey: (keyCode: UInt16, flags: UInt64)? = nil {
        didSet {
            if !isApplyingConfiguration { MappingStore.shared.savePauseHotkey(pauseHotkey) }
        }
    }
    @Published var blacklist: [String] = [] {
        didSet {
            if !isApplyingConfiguration { MappingStore.shared.saveBlacklist(blacklist) }
        }
    }
    // 是否处于按键录制模式（录制期间不拦截按键，让事件正常传递）
    @Published var isRecording: Bool = false

    // MARK: - 私有属性

    // CGEventTap 的 MachPort 引用，用于管理事件监听的生命周期
    private var tap: CFMachPort?
    // Tap 对应的 RunLoop source；重建时需要与旧 MachPort 一并移除。
    private var tapRunLoopSource: CFRunLoopSource?
    // CGEventTap 创建失败时的重试定时器
    private var retryTimer: Timer?
    // 常驻低频巡检，兜底处理撤权、睡眠唤醒或端口失效但未收到禁用回调的情况。
    private var eventTapHealthTimer: Timer?
    // 防止同一轮禁用事件重复提交重建任务。
    private var tapRecoveryScheduled = false
    // 辅助功能权限轮询定时器，授权成功后自动停止
    private var authTimer: Timer?
    // 多映射状态：当同一按键映射到多个目标时，暂存匹配结果等待用户选择
    private var multiMappingState: (keyCode: UInt16, flags: UInt64, modifierCodes: Set<UInt16>, matches: [MyMap])?
    // 单映射按键状态：记录已吞掉的源 keyDown，确保源 keyUp 时补发目标 keyUp 并恢复修饰键状态。
    private var activeSingleMappings: [UInt16: ActiveMapping] = [:]
    // 已吞掉的暂停热键 keyDown；用于屏蔽自动重复并成对吞掉 keyUp。
    private var pauseHotkeyPressedKeyCode: UInt16?
    // 径向选择轮盘是否正在显示
    private var isWheelShowing: Bool = false
    // 自身应用的 Bundle ID，用于在回调中过滤自身应用的按键事件
    private let myBundleId: String? = Bundle.main.bundleIdentifier

    // MARK: - 初始化

    init() {
        list = MappingStore.shared.loadList()
        pauseHotkey = MappingStore.shared.loadPauseHotkey()
        blacklist = MappingStore.shared.loadBlacklist()
        separateGlobalBlacklistFromRulesIfNeeded()
        startEventTapHealthMonitoring()
        checkAccessibility()
    }

    // MARK: - 辅助功能权限检查

    // 检查辅助功能权限是否已授权。
    // 若未授权，启动定时器轮询；授权后立即创建 Tap，而不是提前宣告引擎可用。
    func checkAccessibility() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.checkAccessibility()
            }
            return
        }

        guard AXIsProcessTrusted() else {
            tearDownEventTap()
            scheduleAccessibilityPolling()
            return
        }

        authTimer?.invalidate()
        authTimer = nil

        if let tap, CFMachPortIsValid(tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            updateEventTapActiveState()
        }

        if !isActive {
            start()
        }
    }

    private func scheduleAccessibilityPolling() {
        guard authTimer == nil else { return }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            guard AXIsProcessTrusted() else {
                self.setEventTapActive(false)
                return
            }

            timer.invalidate()
            self.authTimer = nil
            self.start()
        }
        authTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func setEventTapActive(_ active: Bool) {
        if isActive != active {
            isActive = active
        }
    }

    private func updateEventTapActiveState() {
        let tapIsEnabled = tap.map {
            CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0)
        } ?? false
        setEventTapActive(AXIsProcessTrusted() && tapIsEnabled)
    }

    private func startEventTapHealthMonitoring() {
        guard eventTapHealthTimer == nil else { return }

        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkEventTapHealth()
        }
        eventTapHealthTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func checkEventTapHealth() {
        guard AXIsProcessTrusted() else {
            if tap != nil || tapRunLoopSource != nil || isActive {
                tearDownEventTap()
            } else {
                setEventTapActive(false)
            }
            scheduleAccessibilityPolling()
            return
        }

        authTimer?.invalidate()
        authTimer = nil

        guard let tap,
              CFMachPortIsValid(tap),
              CGEvent.tapIsEnabled(tap: tap) else {
            setEventTapActive(false)
            resetInFlightKeyState()
            start()
            return
        }

        setEventTapActive(true)
    }

    // MARK: - 暂停/恢复控制

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    func toggle() {
        if isPaused {
            resume()
        } else {
            pause()
        }
    }

    func applyValidatedConfiguration(_ configuration: MappingStore.ValidatedConfiguration) throws {
        try MappingStore.shared.persistValidatedConfiguration(configuration)

        isApplyingConfiguration = true
        defer { isApplyingConfiguration = false }
        list = configuration.mappings
        blacklist = configuration.blacklist
        pauseHotkey = configuration.pauseHotkey
    }

    // MARK: - 核心事件监听

    private static let eventTag: Int64 = 12345

    private struct ActiveMapping {
        let mapping: MyMap
        let targetModifiers: UInt64
        let targetModifierCodes: Set<UInt16>
        let sourceModifiers: UInt64
        let sourceModifierCodes: Set<UInt16>
    }

    private static let modifierKeyCodes: [UInt16] = [56, 60, 59, 62, 58, 61, 55, 54]

    private static func postEvent(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: eventTag)
        event.post(tap: .cghidEventTap)
    }

    private static func postMappedKey(code: UInt16, flags: UInt64, keyDown: Bool, isAutorepeat: Bool = false) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown) {
            e.flags = CGEventFlags(rawValue: flags)
            e.setIntegerValueField(.keyboardEventAutorepeat, value: isAutorepeat ? 1 : 0)
            postEvent(e)
        }
    }

    private static func postModifierKey(code: UInt16, flags: UInt64, keyDown: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown) {
            e.flags = CGEventFlags(rawValue: flags)
            postEvent(e)
        }
    }

    private static func flags(for modifierCodes: Set<UInt16>) -> UInt64 {
        modifierCodes.reduce(0) { result, code in
            guard let modifier = PhysicalModifierKey.modifier(for: code)?.modifier else { return result }
            return result | modifier.flagValue
        }
    }

    private static func targetModifierCodes(flags: UInt64, sides: ModifierSideSelection) -> Set<UInt16> {
        var result = Set<UInt16>()
        for modifier in ModifierKey.allCases where (flags & modifier.flagValue) != 0 {
            let side = sides.side(for: modifier)
            result.insert(PhysicalModifierKey.keyCode(for: modifier, side: side))
        }
        return result
    }

    private static func postModifierTransition(
        from currentCodes: Set<UInt16>,
        to targetCodes: Set<UInt16>
    ) {
        var activeCodes = currentCodes

        for code in modifierKeyCodes.reversed() where activeCodes.contains(code) && !targetCodes.contains(code) {
            activeCodes.remove(code)
            postModifierKey(code: code, flags: flags(for: activeCodes), keyDown: false)
        }

        for code in modifierKeyCodes where !activeCodes.contains(code) && targetCodes.contains(code) {
            activeCodes.insert(code)
            postModifierKey(code: code, flags: flags(for: activeCodes), keyDown: true)
        }
    }

    private static func postMappedKeyDownWithModifierBridge(
        mapping: MyMap,
        sourceModifierCodes: Set<UInt16>,
        isAutorepeat: Bool
    ) -> (flags: UInt64, codes: Set<UInt16>) {
        let targetModifiers = mapping.tFlags & ModifierKey.allMask
        let targetCodes = targetModifierCodes(flags: targetModifiers, sides: mapping.tModifierSides)
        if !isAutorepeat {
            postModifierTransition(from: sourceModifierCodes, to: targetCodes)
        }
        postMappedKey(code: mapping.tCode, flags: targetModifiers, keyDown: true, isAutorepeat: isAutorepeat)
        return (targetModifiers, targetCodes)
    }

    private static func postMappedKeyUpWithModifierBridge(
        mapping: MyMap,
        targetModifiers: UInt64,
        targetModifierCodes: Set<UInt16>,
        restoreModifierCodes: Set<UInt16>
    ) {
        postMappedKey(code: mapping.tCode, flags: targetModifiers, keyDown: false)
        postModifierTransition(from: targetModifierCodes, to: restoreModifierCodes)
    }

    private static func postMappedKeyPair(code: UInt16, flags: UInt64) {
        postMappedKey(code: code, flags: flags, keyDown: true)
        postMappedKey(code: code, flags: flags, keyDown: false)
    }

    private static func postMappedKeyPairWithModifierBridge(
        mapping: MyMap,
        sourceModifierCodes: Set<UInt16>,
        restoreModifierCodes: Set<UInt16>
    ) {
        let targetModifiers = mapping.tFlags & ModifierKey.allMask
        let targetCodes = targetModifierCodes(flags: targetModifiers, sides: mapping.tModifierSides)
        postModifierTransition(from: sourceModifierCodes, to: targetCodes)
        postMappedKeyPair(code: mapping.tCode, flags: targetModifiers)
        postModifierTransition(from: targetCodes, to: restoreModifierCodes)
    }

    private func shouldHandleMappedKeyUp(keyCode: UInt16) -> Bool {
        activeSingleMappings[keyCode] != nil || multiMappingState?.keyCode == keyCode
    }

    func start() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.start()
            }
            return
        }

        tapRecoveryScheduled = false
        retryTimer?.invalidate()
        retryTimer = nil

        guard AXIsProcessTrusted() else {
            tearDownEventTap()
            scheduleAccessibilityPolling()
            return
        }

        authTimer?.invalidate()
        authTimer = nil

        // 已存在的 Tap 可能只是被系统临时禁用，优先原地恢复。
        if let tap, CFMachPortIsValid(tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            updateEventTapActiveState()
            if isActive {
                return
            }
        }

        tearDownEventTap()

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { (_, type, event, _) -> Unmanaged<CGEvent>? in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                MyEngine.shared.handleEventTapDisabled()
                return Unmanaged.passUnretained(event)
            }

            let c = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let f = event.flags.rawValue

            if event.getIntegerValueField(.eventSourceUserData) == MyEngine.eventTag {
                return Unmanaged.passUnretained(event)
            }

            if type == .flagsChanged {
                ModifierSideTracker.shared.updateFlagsChanged(keyCode: c, flags: f)
                return Unmanaged.passUnretained(event)
            }

            if type == .keyDown || type == .keyUp {
                ModifierSideTracker.shared.updateKeyEvent(keyCode: c, isDown: type == .keyDown)
            }

            if type == .keyUp && MyEngine.shared.shouldHandleMappedKeyUp(keyCode: c) {
                return MyEngine.shared.handleKeyUp(keyCode: c, originalEvent: event)
            }

            if MyEngine.shared.pauseHotkeyPressedKeyCode == c {
                if type == .keyUp {
                    MyEngine.shared.pauseHotkeyPressedKeyCode = nil
                }
                return nil
            }

            if MyEngine.shared.isRecording {
                return Unmanaged.passUnretained(event)
            }

            if let hk = MyEngine.shared.pauseHotkey,
               type == .keyDown,
               c == hk.keyCode,
               (f & ModifierKey.allMask) == (hk.flags & ModifierKey.allMask) {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    MyEngine.shared.pauseHotkeyPressedKeyCode = c
                    DispatchQueue.main.async {
                        MyEngine.shared.toggle()
                    }
                }
                return nil
            }

            if let frontApp = NSWorkspace.shared.frontmostApplication,
               let bundleId = frontApp.bundleIdentifier,
               bundleId == MyEngine.shared.myBundleId {
                return Unmanaged.passUnretained(event)
            }

            if MyEngine.shared.isPaused {
                return Unmanaged.passUnretained(event)
            }

            let currentModifiers = f & ModifierKey.allMask

            if type == .keyDown {
                return MyEngine.shared.handleKeyDown(keyCode: c, modifiers: currentModifiers, isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) == 1, originalEvent: event)
            }

            if type == .keyUp {
                return MyEngine.shared.handleKeyUp(keyCode: c, originalEvent: event)
            }

            return Unmanaged.passUnretained(event)
        }

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: nil
        ) else {
            setEventTapActive(false)
            scheduleEventTapRetry()
            return
        }

        tap = newTap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            tearDownEventTap()
            scheduleEventTapRetry()
            return
        }

        tapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        updateEventTapActiveState()

        if !isActive {
            tearDownEventTap()
            scheduleEventTapRetry()
        }
    }

    // 系统会在回调超时或用户输入保护场景中禁用 Tap。
    // 先尝试原地启用，MachPort 已失效或启用失败时再异步重建。
    private func handleEventTapDisabled() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleEventTapDisabled()
            }
            return
        }

        setEventTapActive(false)
        resetInFlightKeyState()

        if AXIsProcessTrusted(), let tap, CFMachPortIsValid(tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            updateEventTapActiveState()
            if isActive {
                return
            }
        }

        scheduleEventTapRebuild()
    }

    private func scheduleEventTapRebuild() {
        guard !tapRecoveryScheduled else { return }
        tapRecoveryScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tapRecoveryScheduled = false
            self.tearDownEventTap()
            self.start()
        }
    }

    private func scheduleEventTapRetry() {
        guard retryTimer == nil else { return }

        let timer = Timer(timeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.retryTimer = nil
            self?.start()
        }
        retryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tearDownEventTap() {
        resetInFlightKeyState()

        if let source = tapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
            tapRunLoopSource = nil
        }

        if let tap {
            if CFMachPortIsValid(tap) {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
            self.tap = nil
        }

        setEventTapActive(false)
    }

    private func resetInFlightKeyState() {
        let activeMappings = Array(activeSingleMappings.values)
        activeSingleMappings.removeAll()
        for activeMapping in activeMappings {
            Self.postMappedKeyUpWithModifierBridge(
                mapping: activeMapping.mapping,
                targetModifiers: activeMapping.targetModifiers,
                targetModifierCodes: activeMapping.targetModifierCodes,
                restoreModifierCodes: activeMapping.sourceModifierCodes
            )
        }

        if isWheelShowing {
            RadialWheelManager.shared.hide()
        }
        multiMappingState = nil
        isWheelShowing = false
        pauseHotkeyPressedKeyCode = nil
        ModifierSideTracker.shared.reset()
    }

    private func handleKeyDown(keyCode: UInt16, modifiers: UInt64, isAutorepeat: Bool, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if keyCode == 53 && isWheelShowing {
            RadialWheelManager.shared.cancel()
            multiMappingState = nil
            isWheelShowing = false
            return nil
        }

        if multiMappingState != nil && isAutorepeat {
            return nil
        }

        if let state = multiMappingState, state.keyCode != keyCode {
            if isWheelShowing {
                RadialWheelManager.shared.hide()
                isWheelShowing = false
            }
            let m = state.matches[0]
            let restoreFlags = originalEvent.flags.rawValue & ModifierKey.allMask
            Self.postMappedKeyPairWithModifierBridge(
                mapping: m,
                sourceModifierCodes: state.modifierCodes,
                restoreModifierCodes: ModifierSideTracker.shared.physicalCodes(for: restoreFlags)
            )
            if let idx = list.firstIndex(where: { $0.id == m.id }) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .mappingTriggered, object: nil, userInfo: ["index": idx])
                }
            }
            multiMappingState = nil
        }

        let frontBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let matches = list.filter {
            $0.isOn
                && $0.fCode == keyCode
                && ($0.fFlags & ModifierKey.allMask) == modifiers
                && matchesModifierSides($0.fModifierSides, flags: modifiers)
                && !isRuleBlacklisted($0, for: frontBundleId)
        }

        if matches.count > 1 {
            multiMappingState = (
                keyCode,
                modifiers,
                ModifierSideTracker.shared.physicalCodes(for: modifiers),
                matches
            )
            isWheelShowing = true
            let mouseLocation = NSEvent.mouseLocation
            RadialWheelManager.shared.show(mappings: matches, at: mouseLocation)
            return nil
        } else if let m = matches.first {
            let sourceCodes = ModifierSideTracker.shared.physicalCodes(for: modifiers)
            let target = Self.postMappedKeyDownWithModifierBridge(
                mapping: m,
                sourceModifierCodes: sourceCodes,
                isAutorepeat: isAutorepeat
            )
            activeSingleMappings[keyCode] = ActiveMapping(
                mapping: m,
                targetModifiers: target.flags,
                targetModifierCodes: target.codes,
                sourceModifiers: modifiers,
                sourceModifierCodes: sourceCodes
            )
            if let idx = list.firstIndex(where: { $0.id == m.id }) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .mappingTriggered, object: nil, userInfo: ["index": idx])
                }
            }
            return nil
        }

        return Unmanaged.passUnretained(originalEvent)
    }

    private func handleKeyUp(keyCode: UInt16, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if let activeMapping = activeSingleMappings.removeValue(forKey: keyCode) {
            let restoreFlags = originalEvent.flags.rawValue & ModifierKey.allMask
            Self.postMappedKeyUpWithModifierBridge(
                mapping: activeMapping.mapping,
                targetModifiers: activeMapping.targetModifiers,
                targetModifierCodes: activeMapping.targetModifierCodes,
                restoreModifierCodes: ModifierSideTracker.shared.physicalCodes(for: restoreFlags)
            )
            return nil
        }

        if let state = multiMappingState, state.keyCode == keyCode {
            let mapping: MyMap
            if isWheelShowing {
                mapping = RadialWheelManager.shared.getSelectedMapping() ?? state.matches[0]
                RadialWheelManager.shared.hide()
                isWheelShowing = false
            } else {
                mapping = state.matches[0]
            }

            let restoreFlags = originalEvent.flags.rawValue & ModifierKey.allMask
            Self.postMappedKeyPairWithModifierBridge(
                mapping: mapping,
                sourceModifierCodes: state.modifierCodes,
                restoreModifierCodes: ModifierSideTracker.shared.physicalCodes(for: restoreFlags)
            )
            if let idx = list.firstIndex(where: { $0.id == mapping.id }) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .mappingTriggered, object: nil, userInfo: ["index": idx])
                }
            }
            multiMappingState = nil
            return nil
        }

        return Unmanaged.passUnretained(originalEvent)
    }

    private func matchesModifierSides(_ required: ModifierSideSelection, flags: UInt64) -> Bool {
        let held = ModifierSideTracker.shared.heldKeyCodes
        for modifier in [ModifierKey.option, .command] where (flags & modifier.flagValue) != 0 {
            let side = required.side(for: modifier)
            guard side != .any else { continue }
            let pair = PhysicalModifierKey.codes[modifier]!
            let requiredCode = side == .left ? pair.left : pair.right
            let otherCode = side == .left ? pair.right : pair.left
            guard held.contains(requiredCode), !held.contains(otherCode) else { return false }
        }
        return true
    }

    private func isRuleBlacklisted(_ mapping: MyMap, for bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        return blacklist.contains(bundleId) || mapping.appBlacklist.contains(bundleId)
    }

    func addGlobalBlacklistApp(_ bundleId: String) {
        if !blacklist.contains(bundleId) {
            blacklist.append(bundleId)
        }
    }

    private func separateGlobalBlacklistFromRulesIfNeeded() {
        guard !MappingStore.shared.hasSeparatedGlobalBlacklistFromRules() else { return }

        let globalBundleIds = Set(blacklist)
        let copiedGlobalBundleIds = Set(globalBundleIds.filter { bundleId in
            !list.isEmpty && list.allSatisfy { $0.appBlacklist.contains(bundleId) }
        })
        let defaultMappings = MappingStore.defaultMappings()
        let defaultRuleBlacklists = Dictionary(
            uniqueKeysWithValues: defaultMappings.map { ($0.id, Set($0.appBlacklist)) }
        )
        let hasSameKeySignature: (MyMap, MyMap) -> Bool = { lhs, rhs in
            lhs.fCode == rhs.fCode
                && (lhs.fFlags & ModifierKey.allMask) == (rhs.fFlags & ModifierKey.allMask)
                && lhs.fModifierSides == rhs.fModifierSides
                && lhs.tCode == rhs.tCode
                && (lhs.tFlags & ModifierKey.allMask) == (rhs.tFlags & ModifierKey.allMask)
                && lhs.tModifierSides == rhs.tModifierSides
        }
        var normalizedList = list
        var didChange = false
        for idx in normalizedList.indices {
            let beforeCount = normalizedList[idx].appBlacklist.count
            let currentMapping = normalizedList[idx]
            let intrinsicBundleIds: Set<String>
            if let matchedByID = defaultRuleBlacklists[currentMapping.id] {
                intrinsicBundleIds = matchedByID
            } else if let matchedBySignature = defaultMappings.first(where: {
                hasSameKeySignature(currentMapping, $0)
            }) {
                intrinsicBundleIds = Set(matchedBySignature.appBlacklist)
            } else {
                intrinsicBundleIds = []
            }
            normalizedList[idx].appBlacklist.removeAll {
                copiedGlobalBundleIds.contains($0) && !intrinsicBundleIds.contains($0)
            }
            if normalizedList[idx].appBlacklist.count != beforeCount {
                didChange = true
            }
        }

        if didChange {
            list = normalizedList
        }

        MappingStore.shared.markGlobalBlacklistSeparatedFromRules()
    }
}
