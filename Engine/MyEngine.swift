import SwiftUI
import Combine
import AppKit

extension Notification.Name {
    static let mappingTriggered = Notification.Name("mappingTriggered")
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

    // 映射规则列表，变更时自动持久化
    @Published var list: [MyMap] = [] { didSet { MappingStore.shared.saveList(list) } }
    @Published var isActive: Bool = false
    @Published var isPaused: Bool = false
    @Published var pauseHotkey: (keyCode: UInt16, flags: UInt64)? = nil { didSet { MappingStore.shared.savePauseHotkey(pauseHotkey) } }
    @Published var blacklist: [String] = [] { didSet { MappingStore.shared.saveBlacklist(blacklist) } }
    // 是否处于按键录制模式（录制期间不拦截按键，让事件正常传递）
    @Published var isRecording: Bool = false

    // MARK: - 私有属性

    // CGEventTap 的 MachPort 引用，用于管理事件监听的生命周期
    private var tap: CFMachPort?
    // CGEventTap 创建失败时的重试定时器
    private var retryTimer: Timer?
    // 辅助功能权限轮询定时器，授权成功后自动停止
    private var authTimer: Timer?
    // 多映射状态：当同一按键映射到多个目标时，暂存匹配结果等待用户选择
    private var multiMappingState: (keyCode: UInt16, flags: UInt64, matches: [MyMap])?
    // 单映射按键状态：记录已吞掉的源 keyDown，确保源 keyUp 时补发目标 keyUp 并恢复修饰键状态。
    private var activeSingleMappings: [UInt16: ActiveMapping] = [:]
    // 径向选择轮盘是否正在显示
    private var isWheelShowing: Bool = false
    // 自身应用的 Bundle ID，用于在回调中过滤自身应用的按键事件
    private let myBundleId: String? = Bundle.main.bundleIdentifier

    // MARK: - 初始化

    init() {
        list = MappingStore.shared.loadList()
        pauseHotkey = MappingStore.shared.loadPauseHotkey()
        blacklist = MappingStore.shared.loadBlacklist()
        applyGlobalBlacklistToRulesIfNeeded()
        checkAccessibility()
        start()
    }

    // MARK: - 辅助功能权限检查

    // 检查辅助功能权限是否已授权。
    // 若未授权，启动定时器每 0.5 秒轮询一次，授权后自动激活引擎。
    func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        self.isActive = trusted

        if !trusted {
            authTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
                let isNowTrusted = AXIsProcessTrusted()
                if isNowTrusted {
                    DispatchQueue.main.async {
                        self?.isActive = true
                    }
                    timer.invalidate()
                    self?.authTimer = nil
                }
            }
        }
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

    func buildConfigDict() -> [String: Any] {
        [
            "version": "2.0",
            "mappings": list.map { [
                "id": $0.id.uuidString,
                "fCode": $0.fCode,
                "fFlags": $0.fFlags,
                "tCode": $0.tCode,
                "tFlags": $0.tFlags,
                "isOn": $0.isOn,
                "note": $0.note,
                "appBlacklist": $0.appBlacklist
            ]},
            "blacklist": blacklist,
            "pauseHotkey": pauseHotkey.map { [
                "keyCode": $0.keyCode,
                "flags": $0.flags
            ]} as Any
        ]
    }

    // MARK: - 核心事件监听

    private static let eventTag: Int64 = 12345

    private struct ActiveMapping {
        let mapping: MyMap
        let targetModifiers: UInt64
    }

    private static let modifierKeyCodes: [(key: ModifierKey, code: UInt16)] = [
        (.shift, 56),
        (.control, 59),
        (.option, 58),
        (.command, 55)
    ]

    private static func postEvent(_ event: CGEvent, proxy: CGEventTapProxy) {
        event.setIntegerValueField(.eventSourceUserData, value: eventTag)
        event.post(tap: .cghidEventTap)
    }

    private static func postMappedKey(proxy: CGEventTapProxy, code: UInt16, flags: UInt64, keyDown: Bool, isAutorepeat: Bool = false) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown) {
            e.flags = CGEventFlags(rawValue: flags)
            e.setIntegerValueField(.keyboardEventAutorepeat, value: isAutorepeat ? 1 : 0)
            postEvent(e, proxy: proxy)
        }
    }

    private static func postModifierKey(proxy: CGEventTapProxy, code: UInt16, flags: UInt64, keyDown: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown) {
            e.flags = CGEventFlags(rawValue: flags)
            postEvent(e, proxy: proxy)
        }
    }

    private static func postModifierTransition(proxy: CGEventTapProxy, from currentFlags: UInt64, to targetFlags: UInt64) {
        var activeFlags = currentFlags & ModifierKey.allMask
        let targetFlags = targetFlags & ModifierKey.allMask

        for item in modifierKeyCodes.reversed() where (activeFlags & item.key.flagValue) != 0 && (targetFlags & item.key.flagValue) == 0 {
            activeFlags &= ~item.key.flagValue
            postModifierKey(proxy: proxy, code: item.code, flags: activeFlags, keyDown: false)
        }

        for item in modifierKeyCodes where (activeFlags & item.key.flagValue) == 0 && (targetFlags & item.key.flagValue) != 0 {
            activeFlags |= item.key.flagValue
            postModifierKey(proxy: proxy, code: item.code, flags: activeFlags, keyDown: true)
        }
    }

    private static func postMappedKeyDownWithModifierBridge(proxy: CGEventTapProxy, mapping: MyMap, sourceModifiers: UInt64, isAutorepeat: Bool) -> UInt64 {
        let targetModifiers = mapping.tFlags & ModifierKey.allMask
        if !isAutorepeat {
            postModifierTransition(proxy: proxy, from: sourceModifiers, to: targetModifiers)
        }
        postMappedKey(proxy: proxy, code: mapping.tCode, flags: targetModifiers, keyDown: true, isAutorepeat: isAutorepeat)
        return targetModifiers
    }

    private static func postMappedKeyUpWithModifierBridge(proxy: CGEventTapProxy, mapping: MyMap, targetModifiers: UInt64, restoreModifiers: UInt64) {
        postMappedKey(proxy: proxy, code: mapping.tCode, flags: targetModifiers, keyDown: false)
        postModifierTransition(proxy: proxy, from: targetModifiers, to: restoreModifiers)
    }

    private static func postMappedKeyPair(proxy: CGEventTapProxy, code: UInt16, flags: UInt64) {
        postMappedKey(proxy: proxy, code: code, flags: flags, keyDown: true)
        postMappedKey(proxy: proxy, code: code, flags: flags, keyDown: false)
    }

    private static func postMappedKeyPairWithModifierBridge(proxy: CGEventTapProxy, mapping: MyMap, sourceModifiers: UInt64, restoreModifiers: UInt64) {
        let targetModifiers = mapping.tFlags & ModifierKey.allMask
        postModifierTransition(proxy: proxy, from: sourceModifiers, to: targetModifiers)
        postMappedKeyPair(proxy: proxy, code: mapping.tCode, flags: targetModifiers)
        postModifierTransition(proxy: proxy, from: targetModifiers, to: restoreModifiers)
    }

    private func shouldHandleMappedKeyUp(keyCode: UInt16) -> Bool {
        activeSingleMappings[keyCode] != nil || multiMappingState?.keyCode == keyCode
    }

    func start() {
        retryTimer?.invalidate()
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { (proxy, type, event, _) -> Unmanaged<CGEvent>? in
            let c = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let f = event.flags.rawValue

            if event.getIntegerValueField(.eventSourceUserData) == MyEngine.eventTag {
                return Unmanaged.passUnretained(event)
            }

            if type == .keyUp && MyEngine.shared.shouldHandleMappedKeyUp(keyCode: c) {
                return MyEngine.shared.handleKeyUp(proxy: proxy, keyCode: c, originalEvent: event)
            }

            if MyEngine.shared.isRecording {
                return Unmanaged.passUnretained(event)
            }

            if let frontApp = NSWorkspace.shared.frontmostApplication,
               let bundleId = frontApp.bundleIdentifier,
               bundleId == MyEngine.shared.myBundleId {
                return Unmanaged.passUnretained(event)
            }

            if let hk = MyEngine.shared.pauseHotkey {
                if type == .keyDown && c == hk.keyCode && (f & ModifierKey.allMask) == (hk.flags & ModifierKey.allMask) {
                    DispatchQueue.main.async {
                        MyEngine.shared.toggle()
                    }
                    return nil
                }
            }

            if MyEngine.shared.isPaused {
                return Unmanaged.passUnretained(event)
            }

            let currentModifiers = f & ModifierKey.allMask

            if type == .keyDown {
                return MyEngine.shared.handleKeyDown(proxy: proxy, keyCode: c, modifiers: currentModifiers, isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) == 1, originalEvent: event)
            }

            if type == .keyUp {
                return MyEngine.shared.handleKeyUp(proxy: proxy, keyCode: c, originalEvent: event)
            }

            return Unmanaged.passUnretained(event)
        }

        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: nil
        )

        if let t = tap {
            let s = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
            CGEvent.tapEnable(tap: t, enable: true)
            self.isActive = true
        } else {
            self.isActive = false
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.start()
            }
        }
    }

    private func handleKeyDown(proxy: CGEventTapProxy, keyCode: UInt16, modifiers: UInt64, isAutorepeat: Bool, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
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
            Self.postMappedKeyPairWithModifierBridge(proxy: proxy, mapping: m, sourceModifiers: state.flags, restoreModifiers: originalEvent.flags.rawValue & ModifierKey.allMask)
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
                && !isRuleBlacklisted($0, for: frontBundleId)
        }

        if matches.count > 1 {
            multiMappingState = (keyCode, modifiers, matches)
            isWheelShowing = true
            let mouseLocation = NSEvent.mouseLocation
            RadialWheelManager.shared.show(mappings: matches, at: mouseLocation)
            return nil
        } else if let m = matches.first {
            let targetModifiers = Self.postMappedKeyDownWithModifierBridge(proxy: proxy, mapping: m, sourceModifiers: modifiers, isAutorepeat: isAutorepeat)
            activeSingleMappings[keyCode] = ActiveMapping(mapping: m, targetModifiers: targetModifiers)
            if let idx = list.firstIndex(where: { $0.id == m.id }) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .mappingTriggered, object: nil, userInfo: ["index": idx])
                }
            }
            return nil
        }

        return Unmanaged.passUnretained(originalEvent)
    }

    private func handleKeyUp(proxy: CGEventTapProxy, keyCode: UInt16, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if let activeMapping = activeSingleMappings.removeValue(forKey: keyCode) {
            Self.postMappedKeyUpWithModifierBridge(
                proxy: proxy,
                mapping: activeMapping.mapping,
                targetModifiers: activeMapping.targetModifiers,
                restoreModifiers: originalEvent.flags.rawValue & ModifierKey.allMask
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

            Self.postMappedKeyPairWithModifierBridge(
                proxy: proxy,
                mapping: mapping,
                sourceModifiers: state.flags,
                restoreModifiers: originalEvent.flags.rawValue & ModifierKey.allMask
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

    private func isRuleBlacklisted(_ mapping: MyMap, for bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        return mapping.appBlacklist.contains(bundleId)
    }

    func addGlobalBlacklistApp(_ bundleId: String) {
        var didChange = false

        if !blacklist.contains(bundleId) {
            blacklist.append(bundleId)
            didChange = true
        }

        for idx in list.indices where !list[idx].appBlacklist.contains(bundleId) {
            list[idx].appBlacklist.append(bundleId)
            didChange = true
        }

        if didChange {
            MappingStore.shared.saveList(list)
        }
    }

    private func applyGlobalBlacklistToRulesIfNeeded() {
        guard !blacklist.isEmpty,
              !MappingStore.shared.hasMigratedGlobalBlacklist() else { return }

        var didChange = false
        for idx in list.indices {
            let beforeCount = list[idx].appBlacklist.count
            list[idx].mergeAppBlacklist(blacklist)
            if list[idx].appBlacklist.count != beforeCount {
                didChange = true
            }
        }

        if didChange {
            MappingStore.shared.saveList(list)
        }

        MappingStore.shared.markGlobalBlacklistMigrated()
    }
}
