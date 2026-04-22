import SwiftUI
import Combine
import AppKit

class MyEngine: ObservableObject {
    static let shared = MyEngine()
    @Published var list: [MyMap] = [] { didSet { save() } }
    @Published var isActive: Bool = false
    @Published var isPaused: Bool = false
    @Published var pauseHotkey: (keyCode: UInt16, flags: UInt64)? = nil { didSet { savePauseHotkey() } }
    @Published var blacklist: [String] = [] { didSet { saveBlacklist() } }
    @Published var isRecording: Bool = false
    
    private var tap: CFMachPort?
    private var retryTimer: Timer?
    private var authTimer: Timer?
    private var multiMappingState: (keyCode: UInt16, flags: UInt64, matches: [MyMap])?
    private var isWheelShowing: Bool = false
    private let myBundleId: String? = Bundle.main.bundleIdentifier
    
    init() {
        load()
        loadPauseHotkey()
        loadBlacklist()
        checkAccessibility()
        start()
    }
    
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
    
    func save() {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "saved_maps")
        }
    }
    
    func load() {
        if let data = UserDefaults.standard.data(forKey: "saved_maps"),
           let decoded = try? JSONDecoder().decode([MyMap].self, from: data) {
            self.list = decoded
        }
    }
    
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
    
    func loadPauseHotkey() {
        if let data = UserDefaults.standard.data(forKey: "setting_pause_hotkey"),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let keyCode = dict["keyCode"] as? Int,
           let flags = dict["flags"] as? Int {
            self.pauseHotkey = (keyCode: UInt16(keyCode), flags: UInt64(flags))
        } else {
            self.pauseHotkey = (keyCode: 6, flags: 0x120000)
        }
    }
    
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
    
    func start() {
        retryTimer?.invalidate()
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { (proxy, type, event, _) -> Unmanaged<CGEvent>? in
            let c = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let f = event.flags.rawValue

            if event.getIntegerValueField(.eventSourceUserData) == 12345 {
                return Unmanaged.passRetained(event)
            }

            if MyEngine.shared.isRecording {
                return Unmanaged.passRetained(event)
            }

            if let frontApp = NSWorkspace.shared.frontmostApplication,
               let bundleId = frontApp.bundleIdentifier,
               bundleId == MyEngine.shared.myBundleId {
                return Unmanaged.passRetained(event)
            }

            if let hk = MyEngine.shared.pauseHotkey {
                let modifierMask: UInt64 = 0x40000 | 0x80000 | 0x20000 | 0x100000
                if type == .keyDown && c == hk.keyCode && (f & modifierMask) == (hk.flags & modifierMask) {
                    DispatchQueue.main.async {
                        MyEngine.shared.toggle()
                    }
                    return nil
                }
            }

            if MyEngine.shared.isPaused {
                return Unmanaged.passRetained(event)
            }

            if let frontApp = NSWorkspace.shared.frontmostApplication,
               let bundleId = frontApp.bundleIdentifier,
               MyEngine.shared.blacklist.contains(bundleId) {
                return Unmanaged.passRetained(event)
            }

            let modifierMask: UInt64 = 0x40000 | 0x80000 | 0x20000 | 0x100000
            let currentModifiers = f & modifierMask

            if type == .keyDown {
                if c == 53 && MyEngine.shared.isWheelShowing {
                    RadialWheelManager.shared.cancel()
                    MyEngine.shared.multiMappingState = nil
                    MyEngine.shared.isWheelShowing = false
                    return nil
                }

                if MyEngine.shared.multiMappingState != nil && event.getIntegerValueField(.keyboardEventAutorepeat) == 1 {
                    return nil
                }

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

                let matches = MyEngine.shared.list.filter {
                    $0.isOn && $0.fCode == c && ($0.fFlags & modifierMask) == currentModifiers
                }

                if matches.count > 1 {
                    MyEngine.shared.multiMappingState = (c, currentModifiers, matches)
                    MyEngine.shared.isWheelShowing = true
                    let mouseLocation = NSEvent.mouseLocation
                    RadialWheelManager.shared.show(mappings: matches, at: mouseLocation)
                    return nil
                } else if let m = matches.first {
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
                if let state = MyEngine.shared.multiMappingState, state.keyCode == c {
                    let mapping: MyMap
                    if MyEngine.shared.isWheelShowing {
                        mapping = RadialWheelManager.shared.getSelectedMapping() ?? state.matches[0]
                        RadialWheelManager.shared.hide()
                        MyEngine.shared.isWheelShowing = false
                    } else {
                        mapping = state.matches[0]
                    }

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
}
