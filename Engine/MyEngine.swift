import SwiftUI
import Combine
import AppKit

// MARK: - MyEngine
// 核心键盘事件拦截与映射引擎（单例）。
// 这是整个 KeyMapper 最关键的组件，负责在系统级别拦截键盘事件并进行映射。
//
// 工作流程：
// 1. 使用 CGEvent.tapCreate 在系统级别创建键盘事件监听（keyDown/keyUp）
// 2. 在回调中按优先级依次检查：自身事件 → 录制模式 → 自身应用 → 暂停热键 → 暂停状态 → 黑名单
// 3. 匹配映射规则后，构造新的 CGEvent 发送映射后的按键事件
// 4. 同一按键映射到多个目标时，弹出径向选择轮盘（RadialWheel）
//
// 数据持久化：
// - 映射规则、暂停热键、黑名单均通过 UserDefaults + JSON 编码持久化

class MyEngine: ObservableObject {
    static let shared = MyEngine()

    // MARK: - 发布属性（UI 绑定）

    // 映射规则列表，变更时自动持久化
    @Published var list: [MyMap] = [] { didSet { save() } }
    // 引擎是否已激活（辅助功能权限已授权且 CGEventTap 创建成功）
    @Published var isActive: Bool = false
    // 引擎是否暂停（暂停时不做任何映射）
    @Published var isPaused: Bool = false
    // 暂停/恢复热键，默认 Z+Shift+Cmd（keyCode=6, flags=0x120000）
    @Published var pauseHotkey: (keyCode: UInt16, flags: UInt64)? = nil { didSet { savePauseHotkey() } }
    // 黑名单应用 Bundle ID 列表，前台应用在黑名单中时不做映射
    @Published var blacklist: [String] = [] { didSet { saveBlacklist() } }
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
    // 径向选择轮盘是否正在显示
    private var isWheelShowing: Bool = false
    // 自身应用的 Bundle ID，用于在回调中过滤自身应用的按键事件
    private let myBundleId: String? = Bundle.main.bundleIdentifier

    // MARK: - 初始化

    init() {
        load()
        loadPauseHotkey()
        loadBlacklist()
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

    // MARK: - 映射规则持久化

    // 将映射规则列表编码为 JSON 并保存到 UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "saved_maps")
        }
    }

    // 从 UserDefaults 加载映射规则列表
    func load() {
        if let data = UserDefaults.standard.data(forKey: "saved_maps"),
           let decoded = try? JSONDecoder().decode([MyMap].self, from: data) {
            self.list = decoded
        }
    }

    // MARK: - 暂停热键持久化

    // 将暂停热键保存为 JSON 字典到 UserDefaults
    func savePauseHotkey() {
        if let hk = pauseHotkey {
            let dict: [String: Any] = ["keyCode": Int(hk.keyCode), "flags": Int(hk.flags)]
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                UserDefaults.standard.set(data, forKey: "setting_pause_hotkey")
            }
        } else {
            UserDefaults.standard.removeObject(forKey: "setting_pause_hotkey")
        }
    }

    // 从 UserDefaults 加载暂停热键，未设置时使用默认值 Z+Shift+Cmd
    func loadPauseHotkey() {
        if let data = UserDefaults.standard.data(forKey: "setting_pause_hotkey"),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let keyCode = dict["keyCode"] as? Int,
           let flags = dict["flags"] as? Int {
            self.pauseHotkey = (keyCode: UInt16(keyCode), flags: UInt64(flags))
        } else {
            // 默认暂停热键：Z + Shift + Command
            self.pauseHotkey = (keyCode: 6, flags: 0x120000)
        }
    }

    // MARK: - 黑名单持久化

    func saveBlacklist() {
        if let data = try? JSONEncoder().encode(blacklist) {
            UserDefaults.standard.set(data, forKey: "setting_blacklist")
        }
    }

    func loadBlacklist() {
        if let data = UserDefaults.standard.data(forKey: "setting_blacklist"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.blacklist = decoded
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

    // MARK: - 核心事件监听

    // 创建 CGEventTap 并启动键盘事件监听。
    // 事件处理回调中的优先级链：
    //   1. 自身发送的事件（eventSourceUserData == 12345）→ 直接放行，防止无限循环
    //   2. 录制模式 → 放行，让按键事件正常传递给 UI
    //   3. 自身应用 → 放行，避免拦截自身窗口的按键
    //   4. 暂停热键 → 拦截并切换暂停状态
    //   5. 暂停状态 → 放行所有事件
    //   6. 黑名单应用 → 放行
    //   7. 映射规则匹配 → 单映射直接替换 / 多映射弹出轮盘
    //
    // 多映射处理流程：
    //   - keyDown 时：匹配到多个映射 → 吞掉原始事件，弹出径向轮盘，等待用户选择
    //   - keyUp 时：用户已通过鼠标选择目标 → 发送选中映射的 keyDown+keyUp
    //   - 若 keyUp 时用户未选择 → 默认使用第一个映射
    //   - 若 keyDown 后用户按了其他键 → 取消轮盘，使用第一个映射并发送
    func start() {
        retryTimer?.invalidate()
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { (proxy, type, event, _) -> Unmanaged<CGEvent>? in
            let c = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let f = event.flags.rawValue

            // [1] 自身发送的映射事件，标记 eventSourceUserData=12345，直接放行防止无限循环
            if event.getIntegerValueField(.eventSourceUserData) == 12345 {
                return Unmanaged.passRetained(event)
            }

            // [2] 录制模式下放行所有按键，让 UI 正常接收
            if MyEngine.shared.isRecording {
                return Unmanaged.passRetained(event)
            }

            // [3] 自身应用前台的按键不做拦截
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               let bundleId = frontApp.bundleIdentifier,
               bundleId == MyEngine.shared.myBundleId {
                return Unmanaged.passRetained(event)
            }

            // [4] 检测暂停热键（仅 keyDown 时触发）
            if let hk = MyEngine.shared.pauseHotkey {
                // modifierMask: 仅检查 Ctrl/Alt/Shift/Cmd 四个修饰键
                let modifierMask: UInt64 = 0x40000 | 0x80000 | 0x20000 | 0x100000
                if type == .keyDown && c == hk.keyCode && (f & modifierMask) == (hk.flags & modifierMask) {
                    DispatchQueue.main.async {
                        MyEngine.shared.toggle()
                    }
                    return nil
                }
            }

            // [5] 暂停状态下放行所有事件
            if MyEngine.shared.isPaused {
                return Unmanaged.passRetained(event)
            }

            // [6] 黑名单应用前台时放行
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               let bundleId = frontApp.bundleIdentifier,
               MyEngine.shared.blacklist.contains(bundleId) {
                return Unmanaged.passRetained(event)
            }

            // 提取当前修饰键状态（仅 Ctrl/Alt/Shift/Cmd）
            let modifierMask: UInt64 = 0x40000 | 0x80000 | 0x20000 | 0x100000
            let currentModifiers = f & modifierMask

            // [7] 映射规则匹配与处理
            if type == .keyDown {
                // Esc 键取消径向轮盘
                if c == 53 && MyEngine.shared.isWheelShowing {
                    RadialWheelManager.shared.cancel()
                    MyEngine.shared.multiMappingState = nil
                    MyEngine.shared.isWheelShowing = false
                    return nil
                }

                // 多映射等待期间，忽略自动重复按键
                if MyEngine.shared.multiMappingState != nil && event.getIntegerValueField(.keyboardEventAutorepeat) == 1 {
                    return nil
                }

                // 多映射等待期间按了其他键：取消轮盘，使用第一个映射并发送
                if let state = MyEngine.shared.multiMappingState, state.keyCode != c {
                    if MyEngine.shared.isWheelShowing {
                        RadialWheelManager.shared.hide()
                        MyEngine.shared.isWheelShowing = false
                    }
                    let m = state.matches[0]
                    let internalSource = CGEventSource(stateID: .combinedSessionState)
                    if let keyDown = CGEvent(keyboardEventSource: internalSource, virtualKey: m.tCode, keyDown: true) {
                        keyDown.flags = CGEventFlags(rawValue: m.tFlags)
                        keyDown.setIntegerValueField(.eventSourceUserData, value: 12345)
                        keyDown.tapPostEvent(proxy)
                    }
                    if let keyUp = CGEvent(keyboardEventSource: internalSource, virtualKey: m.tCode, keyDown: false) {
                        keyUp.flags = CGEventFlags(rawValue: m.tFlags)
                        keyUp.setIntegerValueField(.eventSourceUserData, value: 12345)
                        keyUp.tapPostEvent(proxy)
                    }
                    MyEngine.shared.multiMappingState = nil
                }

                // 查找当前按键匹配的映射规则（启用 + keyCode + 修饰键均匹配）
                let matches = MyEngine.shared.list.filter {
                    $0.isOn && $0.fCode == c && ($0.fFlags & modifierMask) == currentModifiers
                }

                if matches.count > 1 {
                    // 多映射：暂存状态，弹出径向轮盘等待用户选择
                    MyEngine.shared.multiMappingState = (c, currentModifiers, matches)
                    MyEngine.shared.isWheelShowing = true
                    let mouseLocation = NSEvent.mouseLocation
                    RadialWheelManager.shared.show(mappings: matches, at: mouseLocation)
                    return nil
                } else if let m = matches.first {
                    // 单映射：直接构造并发送映射后的按键事件
                    let internalSource = CGEventSource(stateID: .combinedSessionState)
                    if let e = CGEvent(keyboardEventSource: internalSource, virtualKey: m.tCode, keyDown: type == .keyDown) {
                        e.flags = CGEventFlags(rawValue: m.tFlags)
                        e.setIntegerValueField(.eventSourceUserData, value: 12345)
                        e.tapPostEvent(proxy)
                        return nil
                    }
                }
            }

            if type == .keyUp {
                // 多映射状态下原始按键释放：用户已通过鼠标选择目标，发送选中映射的按键
                if let state = MyEngine.shared.multiMappingState, state.keyCode == c {
                    let mapping: MyMap
                    if MyEngine.shared.isWheelShowing {
                        // 轮盘仍在显示，取用户选中的映射；未选中则默认第一个
                        mapping = RadialWheelManager.shared.getSelectedMapping() ?? state.matches[0]
                        RadialWheelManager.shared.hide()
                        MyEngine.shared.isWheelShowing = false
                    } else {
                        // 轮盘已消失（用户已选择），使用第一个映射
                        mapping = state.matches[0]
                    }

                    // 发送映射后的 keyDown + keyUp 组合
                    let internalSource = CGEventSource(stateID: .combinedSessionState)
                    if let keyDown = CGEvent(keyboardEventSource: internalSource, virtualKey: mapping.tCode, keyDown: true) {
                        keyDown.flags = CGEventFlags(rawValue: mapping.tFlags)
                        keyDown.setIntegerValueField(.eventSourceUserData, value: 12345)
                        keyDown.tapPostEvent(proxy)
                    }
                    if let keyUp = CGEvent(keyboardEventSource: internalSource, virtualKey: mapping.tCode, keyDown: false) {
                        keyUp.flags = CGEventFlags(rawValue: mapping.tFlags)
                        keyUp.setIntegerValueField(.eventSourceUserData, value: 12345)
                        keyUp.tapPostEvent(proxy)
                    }

                    MyEngine.shared.multiMappingState = nil
                    return nil
                }
            }

            return Unmanaged.passRetained(event)
        }

        // 创建 CGEventTap：在会话级别拦截键盘事件，插入位置为头部（最先处理）
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: nil
        )

        if let t = tap {
            // 将事件源添加到主线程 RunLoop，使回调在主线程执行
            let s = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
            CGEvent.tapEnable(tap: t, enable: true)
            self.isActive = true
        } else {
            // 创建失败（通常因权限不足），2 秒后重试
            self.isActive = false
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.start()
            }
        }
    }
}
