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
// 1. 使用 CGEvent.tapCreate 监听键盘、修饰键变化及携带修饰键的鼠标事件
// 2. 在回调中按优先级依次检查：自身事件 → 录制模式 → 自身应用 → 暂停热键 → 暂停状态 → 规则级黑名单
// 3. 匹配映射规则后，构造新的 CGEvent 发送映射后的按键事件
// 4. 同一按键映射到多个目标时，弹出径向选择轮盘（RadialWheel）
//
// 数据持久化：
// - 快捷键/修饰键规则、全局黑名单、暂停热键通过 UserDefaults + JSON 编码持久化

class MyEngine: ObservableObject {
    static let shared = MyEngine()

    // MARK: - 发布属性（UI 绑定）

    private var isApplyingConfiguration = false
    private let persistsConfiguration: Bool
    private let eventPoster: ((CGEvent, CGEventTapProxy?) -> Void)?
    private let frontmostBundleID: () -> String?
    // 映射规则列表，变更时自动持久化
    @Published var list: [MyMap] = [] {
        didSet {
            if !isApplyingConfiguration {
                if persistsConfiguration { MappingStore.shared.saveList(list) }
                cancelModifierSourceMappings()
                refreshModifierOutput()
            }
        }
    }
    @Published var isActive: Bool = false
    @Published var modifierMappings: [ModifierMapping] = [] {
        didSet {
            if !isApplyingConfiguration {
                if persistsConfiguration { MappingStore.shared.saveModifierMappings(modifierMappings) }
                cancelModifierSourceMappings()
                refreshModifierOutput()
            }
        }
    }
    @Published var isPaused: Bool = false {
        didSet { if isPaused != oldValue { cancelModifierSourceMappings(); refreshModifierOutput() } }
    }
    @Published var pauseHotkey: (keyCode: UInt16, flags: UInt64)? = nil {
        didSet {
            if !isApplyingConfiguration && persistsConfiguration { MappingStore.shared.savePauseHotkey(pauseHotkey) }
        }
    }
    @Published var blacklist: [String] = [] {
        didSet {
            if !isApplyingConfiguration {
                if persistsConfiguration { MappingStore.shared.saveBlacklist(blacklist) }
                cancelModifierSourceMappings()
                refreshModifierOutput()
            }
        }
    }
    // 是否处于按键录制模式（录制期间不拦截按键，让事件正常传递）
    @Published var isRecording: Bool = false {
        didSet { if isRecording != oldValue { cancelModifierSourceMappings(); refreshModifierOutput() } }
    }

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
    private var multiMappingState: (keyCode: UInt16, matches: [MyMap])?
    // 单映射按键状态：记录已吞掉的源 keyDown，确保源 keyUp 时补发目标 keyUp 并恢复修饰键状态。
    private var activeSingleMappings: [UInt16: ActiveMapping] = [:]
    private var modifierOutput = ModifierRemappingState()
    private var lastPhysicalFlags: UInt64 = 0
    private var modifierSessionSuspended = false
    private var modifierActionBundleID: String?
    private var modifierObservers = Set<AnyCancellable>()
    private var suppressedKeyUps = Set<UInt16>()
    // 已吞掉的暂停热键 keyDown；用于屏蔽自动重复并成对吞掉 keyUp。
    private var pauseHotkeyPressedKeyCode: UInt16?
    // 径向选择轮盘是否正在显示
    private var isWheelShowing: Bool = false
    // 自身应用的 Bundle ID，用于在回调中过滤自身应用的按键事件
    private let myBundleId: String? = Bundle.main.bundleIdentifier

    // MARK: - 初始化

    init(
        startMonitoring: Bool = true,
        eventPoster: ((CGEvent, CGEventTapProxy?) -> Void)? = nil,
        frontmostBundleID: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    ) {
        persistsConfiguration = startMonitoring
        self.eventPoster = eventPoster
        self.frontmostBundleID = frontmostBundleID
        guard startMonitoring else { return }
        list = MappingStore.shared.loadList()
        modifierMappings = MappingStore.shared.loadModifierMappings()
        pauseHotkey = MappingStore.shared.loadPauseHotkey()
        blacklist = MappingStore.shared.loadBlacklist()
        separateGlobalBlacklistFromRulesIfNeeded()
        observeModifierContext()
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
        defer {
            isApplyingConfiguration = false
            cancelModifierSourceMappings()
            refreshModifierOutput()
        }
        list = configuration.mappings
        modifierMappings = configuration.modifierMappings
        blacklist = configuration.blacklist
        pauseHotkey = configuration.pauseHotkey
    }

    // MARK: - 核心事件监听

    private static let eventTag: Int64 = 12345

    private struct ActiveMapping {
        let mapping: MyMap
        let targetModifierCodes: Set<UInt16>
        let sourceModifierCodes: Set<UInt16>
    }

    private func postEvent(_ event: CGEvent, proxy: CGEventTapProxy? = nil) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        if let eventPoster {
            eventPoster(event, proxy)
        } else if let proxy {
            // 在当前回调返回的事件之前发送，避免后续字母/鼠标事件抢在修饰键前面。
            event.tapPostEvent(proxy)
        } else {
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func postMappedKey(code: UInt16, flags: UInt64, keyDown: Bool, isAutorepeat: Bool = false, proxy: CGEventTapProxy? = nil) {
        let source = CGEventSource(stateID: .privateState)
        if let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown) {
            event.flags = CGEventFlags(rawValue: flags)
            event.setIntegerValueField(.keyboardEventAutorepeat, value: isAutorepeat ? 1 : 0)
            postEvent(event, proxy: proxy)
        }
    }

    private var outputFlags: UInt64 {
        ModifierRemappingState.flags(for: modifierOutput.outputCodes, preserving: lastPhysicalFlags)
    }

    private var mappedKeyFlags: UInt64 {
        // 目标快捷键使用明确指定的修饰键，不能继承源方向键/Fn 键的专用标志。
        ModifierRemappingState.flags(for: modifierOutput.outputCodes, preserving: 0)
    }

    private var eligibleModifierRules: [MyMap] {
        let bundleID = frontmostBundleID()
        guard !isPaused, !isRecording, !modifierSessionSuspended,
              bundleID == nil || bundleID != myBundleId else { return [] }
        return (list + modifierMappings.map(\.rule)).filter {
            $0.isOn && $0.sourceModifier != nil && isRuleAllowed($0, for: bundleID)
        }
    }

    private func mappedModifierCodes(_ physicalCodes: Set<UInt16>) -> Set<UInt16> {
        ModifierRemappingState.mappedCodes(
            physicalCodes, rules: ModifierRemappingState.continuousRules(from: eligibleModifierRules),
            bundleID: frontmostBundleID(), enabled: true
        )
    }

    private var desiredModifierCodes: Set<UInt16> {
        guard !modifierSessionSuspended else { return [] }
        // 已命中的快捷键优先，输出目标修饰键；物理键状态始终单独保存。
        var base = mappedModifierCodes(ModifierSideTracker.shared.heldKeyCodes)
        if let pending = multiMappingState,
           let modifier = PhysicalModifierKey.modifier(for: pending.keyCode)?.modifier,
           let pair = PhysicalModifierKey.codes[modifier] {
            base.subtract(mappedModifierCodes([pair.left, pair.right]))
        }
        return ModifierRemappingState.applyingShortcuts(
            to: base,
            overrides: activeSingleMappings.values.map {
                (source: mappedModifierCodes($0.sourceModifierCodes), target: $0.targetModifierCodes)
            }
        )
    }

    private func postModifierChanges(_ changes: [ModifierRemappingState.Change], proxy: CGEventTapProxy? = nil) {
        for change in changes {
            let source = CGEventSource(stateID: .privateState)
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: change.keyCode, keyDown: change.isDown) else { continue }
            event.type = .flagsChanged
            event.flags = CGEventFlags(rawValue: change.flags)
            postEvent(event, proxy: proxy)
        }
    }

    private func transitionModifiers(to codes: Set<UInt16>, proxy: CGEventTapProxy? = nil) {
        postModifierChanges(modifierOutput.transition(to: codes, preserving: lastPhysicalFlags), proxy: proxy)
    }

    private func refreshModifierOutput(proxy: CGEventTapProxy? = nil) {
        guard tap != nil || eventPoster != nil, !isApplyingConfiguration else { return }
        cancelUnavailableMappings(proxy: proxy)
        transitionModifiers(to: desiredModifierCodes, proxy: proxy)
    }

    private func postMappedKeyPairWithModifierBridge(mapping: MyMap, proxy: CGEventTapProxy?) {
        var codes = mapping.outputModifierCodes
        for active in activeSingleMappings.values { codes.formUnion(active.targetModifierCodes) }
        transitionModifiers(to: codes, proxy: proxy)
        if mapping.targetModifier == nil {
            postMappedKey(code: mapping.tCode, flags: mappedKeyFlags, keyDown: true, proxy: proxy)
            postMappedKey(code: mapping.tCode, flags: mappedKeyFlags, keyDown: false, proxy: proxy)
        }
        refreshModifierOutput(proxy: proxy)
    }

    private func cancelModifierSourceMappings(proxy: CGEventTapProxy? = nil) {
        for (key, active) in Array(activeSingleMappings) where active.mapping.sourceModifier != nil {
            if active.mapping.targetModifier == nil {
                postMappedKey(code: active.mapping.tCode, flags: mappedKeyFlags, keyDown: false, proxy: proxy)
            }
            activeSingleMappings.removeValue(forKey: key)
        }
        if let pending = multiMappingState, PhysicalModifierKey.modifier(for: pending.keyCode) != nil {
            RadialWheelManager.shared.hide()
            multiMappingState = nil
            isWheelShowing = false
        }
    }

    private func updateModifierActionContext(proxy: CGEventTapProxy? = nil) {
        cancelUnavailableMappings(proxy: proxy)
        let bundleID = frontmostBundleID()
        guard bundleID != modifierActionBundleID else { return }
        cancelModifierSourceMappings(proxy: proxy)
        modifierActionBundleID = bundleID
    }

    private func handleModifierSource(proxy: CGEventTapProxy?, keyCode: UInt16, previouslyHeld: Set<UInt16>, event: CGEvent) {
        guard let modifier = PhysicalModifierKey.modifier(for: keyCode)?.modifier,
              let pair = PhysicalModifierKey.codes[modifier] else { return }
        let sourceCodes: Set<UInt16> = [pair.left, pair.right]
        let wasHeld = !previouslyHeld.isDisjoint(with: sourceCodes)
        let isHeld = !ModifierSideTracker.shared.heldKeyCodes.isDisjoint(with: sourceCodes)
        if activeSingleMappings[pair.left]?.mapping.sourceModifier != nil || multiMappingState?.keyCode == pair.left {
            if !isHeld { _ = handleKeyUp(proxy: proxy, keyCode: pair.left, originalEvent: event) }
            return
        }
        guard !wasHeld, isHeld, multiMappingState == nil else { return }
        let matches = eligibleModifierRules.filter { $0.sourceModifier == modifier }
        if matches.count > 1 {
            multiMappingState = (pair.left, matches)
            isWheelShowing = true
            RadialWheelManager.shared.show(mappings: matches, at: NSEvent.mouseLocation)
            refreshModifierOutput(proxy: proxy)
        } else if let mapping = matches.first, mapping.targetModifier == nil {
            // 修饰键 → 普通键/组合键与其他映射一样成对发送，两个物理侧别共享按住状态。
            activeSingleMappings[pair.left] = ActiveMapping(
                mapping: mapping, targetModifierCodes: mapping.outputModifierCodes,
                sourceModifierCodes: sourceCodes
            )
            refreshModifierOutput(proxy: proxy)
            postMappedKey(code: mapping.tCode, flags: mappedKeyFlags, keyDown: true, proxy: proxy)
            if let index = list.firstIndex(where: { $0.id == mapping.id }) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .mappingTriggered, object: nil, userInfo: ["index": index])
                }
            }
        }
    }

    private func observeModifierContext() {
        let center = NSWorkspace.shared.notificationCenter
        center.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateModifierActionContext()
                self?.refreshModifierOutput()
            }
            .store(in: &modifierObservers)
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            center.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }
                self.modifierSessionSuspended = true
                self.resetInFlightKeyState(restorePhysical: false)
            }.store(in: &modifierObservers)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            center.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }
                self.modifierSessionSuspended = false
                ModifierSideTracker.shared.synchronizeWithKeyboard()
                self.refreshModifierOutput()
            }.store(in: &modifierObservers)
        }
    }

    // 退出前恢复物理修饰键，避免遗留由本程序按下的逻辑键。
    func stop() {
        eventTapHealthTimer?.invalidate()
        retryTimer?.invalidate()
        authTimer?.invalidate()
        tearDownEventTap()
    }

    func handleEvent(proxy: CGEventTapProxy?, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            handleEventTapDisabled()
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.eventTag {
            return Unmanaged.passUnretained(event)
        }

        updateModifierActionContext(proxy: proxy)
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let physicalFlags = event.flags.rawValue
        lastPhysicalFlags = physicalFlags

        if type == .flagsChanged {
            let previouslyHeld = ModifierSideTracker.shared.heldKeyCodes
            ModifierSideTracker.shared.updateFlagsChanged(keyCode: code, flags: physicalFlags)
            handleModifierSource(proxy: proxy, keyCode: code, previouslyHeld: previouslyHeld, event: event)
            let changes = modifierOutput.transition(to: desiredModifierCodes, preserving: physicalFlags)
            if PhysicalModifierKey.modifier(for: code) != nil {
                if changes.count == 1, changes[0].keyCode == code {
                    event.flags = CGEventFlags(rawValue: outputFlags)
                    return Unmanaged.passUnretained(event)
                }
                postModifierChanges(changes, proxy: proxy)
                return nil
            }
            // Caps Lock / Fn 保持原事件，只同步其中携带的标准修饰键状态。
            postModifierChanges(changes, proxy: proxy)
            event.flags = CGEventFlags(rawValue: outputFlags)
            return Unmanaged.passUnretained(event)
        }

        // 安全输入或 Tap 暂停期间可能漏掉 flagsChanged；从物理状态恢复。
        if (ModifierRemappingState.flags(for: ModifierSideTracker.shared.heldKeyCodes, preserving: 0) & ModifierKey.allMask)
            != (physicalFlags & ModifierKey.allMask) {
            ModifierSideTracker.shared.synchronizeWithKeyboard()
        }
        refreshModifierOutput(proxy: proxy)
        event.flags = CGEventFlags(rawValue: outputFlags)
        guard type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }

        if type == .keyUp, suppressedKeyUps.remove(code) != nil { return nil }
        if type == .keyDown, suppressedKeyUps.contains(code) {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 1 { return nil }
            suppressedKeyUps.remove(code)
        }
        if type == .keyUp && shouldHandleMappedKeyUp(keyCode: code) {
            return handleKeyUp(proxy: proxy, keyCode: code, originalEvent: event)
        }
        if pauseHotkeyPressedKeyCode == code {
            if type == .keyUp { pauseHotkeyPressedKeyCode = nil }
            return nil
        }
        if isRecording { return Unmanaged.passUnretained(event) }

        // 暂停热键及快捷键规则始终匹配物理输入，修饰键映射不会改变现有规则含义。
        if let hotkey = pauseHotkey, type == .keyDown, code == hotkey.keyCode,
           (physicalFlags & ModifierKey.allMask) == (hotkey.flags & ModifierKey.allMask) {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                pauseHotkeyPressedKeyCode = code
                DispatchQueue.main.async { MyEngine.shared.toggle() }
            }
            return nil
        }
        if isPaused || modifierSessionSuspended || frontmostBundleID() == myBundleId {
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            return handleKeyDown(proxy: proxy, keyCode: code, modifiers: physicalFlags & ModifierKey.allMask,
                isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) == 1, originalEvent: event)
        }
        return handleKeyUp(proxy: proxy, keyCode: code, originalEvent: event)
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
                ModifierSideTracker.shared.synchronizeWithKeyboard()
                refreshModifierOutput()
                return
            }
        }

        tearDownEventTap()

        let eventTypes: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
        ]
        let mask = eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { (proxy, type, event, _) in
            MyEngine.shared.handleEvent(proxy: proxy, type: type, event: event)
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
        ModifierSideTracker.shared.synchronizeWithKeyboard()
        modifierOutput.synchronize(to: ModifierSideTracker.shared.heldKeyCodes)
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            tearDownEventTap()
            scheduleEventTapRetry()
            return
        }

        tapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        updateEventTapActiveState()
        refreshModifierOutput()

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
                ModifierSideTracker.shared.synchronizeWithKeyboard()
                refreshModifierOutput()
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

    private func resetInFlightKeyState(restorePhysical: Bool = true) {
        suppressedKeyUps.formUnion(activeSingleMappings.filter { $0.value.mapping.sourceModifier == nil }.keys)
        if let pending = multiMappingState, PhysicalModifierKey.modifier(for: pending.keyCode) == nil { suppressedKeyUps.insert(pending.keyCode) }
        for activeMapping in activeSingleMappings.values where activeMapping.mapping.targetModifier == nil {
            postMappedKey(code: activeMapping.mapping.tCode, flags: mappedKeyFlags, keyDown: false)
        }
        activeSingleMappings.removeAll()
        if tap != nil || eventPoster != nil {
            if restorePhysical && !modifierSessionSuspended {
                if persistsConfiguration { ModifierSideTracker.shared.synchronizeWithKeyboard() }
                transitionModifiers(to: ModifierSideTracker.shared.heldKeyCodes)
            } else {
                transitionModifiers(to: [])
            }
        } else {
            modifierOutput.synchronize(to: [])
        }

        if isWheelShowing {
            RadialWheelManager.shared.hide()
        }
        multiMappingState = nil
        isWheelShowing = false
        pauseHotkeyPressedKeyCode = nil
        ModifierSideTracker.shared.reset()
    }

    private func handleKeyDown(proxy: CGEventTapProxy?, keyCode: UInt16, modifiers: UInt64, isAutorepeat: Bool, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if let active = activeSingleMappings[keyCode] {
            if active.mapping.targetModifier == nil {
                postMappedKey(code: active.mapping.tCode, flags: mappedKeyFlags, keyDown: true, isAutorepeat: isAutorepeat, proxy: proxy)
            }
            return nil
        }
        if keyCode == 53 && isWheelShowing {
            RadialWheelManager.shared.cancel()
            multiMappingState = nil
            isWheelShowing = false
            refreshModifierOutput(proxy: proxy)
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
            postMappedKeyPairWithModifierBridge(mapping: m, proxy: proxy)
            if let idx = list.firstIndex(where: { $0.id == m.id }) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .mappingTriggered, object: nil, userInfo: ["index": idx])
                }
            }
            multiMappingState = nil
            refreshModifierOutput(proxy: proxy)
            originalEvent.flags = CGEventFlags(rawValue: outputFlags)
        }

        let frontBundleId = frontmostBundleID()
        let matches = list.filter {
            $0.isOn
                && $0.fCode == keyCode
                && ($0.fFlags & ModifierKey.allMask) == modifiers
                && matchesModifierSides($0.fModifierSides, flags: modifiers)
                && isRuleAllowed($0, for: frontBundleId)
        }

        if matches.count > 1 {
            multiMappingState = (keyCode, matches)
            isWheelShowing = true
            let mouseLocation = NSEvent.mouseLocation
            RadialWheelManager.shared.show(mappings: matches, at: mouseLocation)
            return nil
        } else if let m = matches.first {
            let sourceCodes = ModifierSideTracker.shared.physicalCodes(for: modifiers)
            activeSingleMappings[keyCode] = ActiveMapping(
                mapping: m,
                targetModifierCodes: m.outputModifierCodes,
                sourceModifierCodes: sourceCodes
            )
            refreshModifierOutput(proxy: proxy)
            if m.targetModifier == nil {
                postMappedKey(code: m.tCode, flags: mappedKeyFlags, keyDown: true, isAutorepeat: isAutorepeat, proxy: proxy)
            }
            if let idx = list.firstIndex(where: { $0.id == m.id }) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .mappingTriggered, object: nil, userInfo: ["index": idx])
                }
            }
            return nil
        }

        return Unmanaged.passUnretained(originalEvent)
    }

    private func handleKeyUp(proxy: CGEventTapProxy?, keyCode: UInt16, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if let activeMapping = activeSingleMappings.removeValue(forKey: keyCode) {
            if activeMapping.mapping.targetModifier == nil {
                postMappedKey(code: activeMapping.mapping.tCode, flags: mappedKeyFlags, keyDown: false, proxy: proxy)
            }
            refreshModifierOutput(proxy: proxy)
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

            postMappedKeyPairWithModifierBridge(mapping: mapping, proxy: proxy)
            if let idx = list.firstIndex(where: { $0.id == mapping.id }) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .mappingTriggered, object: nil, userInfo: ["index": idx])
                }
            }
            multiMappingState = nil
            refreshModifierOutput(proxy: proxy)
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

    private func isRuleAllowed(_ mapping: MyMap, for bundleId: String?) -> Bool {
        if let bundleId, blacklist.contains(bundleId) { return false }
        return mapping.allowsApplication(bundleId)
    }

    // 应用范围变化后释放已发送的目标键，吞掉仍被按住的源键后续重复和松开事件。
    private func cancelUnavailableMappings(proxy: CGEventTapProxy? = nil) {
        guard !activeSingleMappings.isEmpty || multiMappingState != nil else { return }
        let bundleID = frontmostBundleID()
        let currentRules = list + modifierMappings.map(\.rule)
        func isAvailable(_ mapping: MyMap) -> Bool {
            guard let current = currentRules.first(where: { $0.id == mapping.id }) else { return false }
            return current.isOn && isRuleAllowed(current, for: bundleID)
        }
        for (key, active) in Array(activeSingleMappings) where !isAvailable(active.mapping) {
            if active.mapping.targetModifier == nil {
                postMappedKey(code: active.mapping.tCode, flags: mappedKeyFlags, keyDown: false, proxy: proxy)
            }
            activeSingleMappings.removeValue(forKey: key)
            if active.mapping.sourceModifier == nil { suppressedKeyUps.insert(key) }
        }
        if let pending = multiMappingState,
           pending.matches.contains(where: { !isAvailable($0) }) {
            if PhysicalModifierKey.modifier(for: pending.keyCode) == nil { suppressedKeyUps.insert(pending.keyCode) }
            RadialWheelManager.shared.hide()
            multiMappingState = nil
            isWheelShowing = false
        }
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
