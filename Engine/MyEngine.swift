import SwiftUI
import Combine
import AppKit

class MyEngine: ObservableObject {
    static let shared = MyEngine()
    @Published var list: [MyMap] = [] { didSet { save() } }
    @Published var isActive: Bool = false
    @Published var isPaused: Bool = false
    @Published var pauseHotkey: (keyCode: UInt16, flags: UInt64)? = nil { didSet { savePauseHotkey() } }
    
    private var tap: CFMachPort?
    private var retryTimer: Timer?
    private var authTimer: Timer?
    
    init() {
        load()
        loadPauseHotkey()
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
            
            let modifierMask: UInt64 = 0x40000 | 0x80000 | 0x20000 | 0x100000
            let currentModifiers = f & modifierMask
            
            if let m = MyEngine.shared.list.first(where: {
                $0.isOn && $0.fCode == c && ($0.fFlags & modifierMask) == currentModifiers
            }) {
                let internalSource = CGEventSource(stateID: .combinedSessionState)
                if let e = CGEvent(keyboardEventSource: internalSource, virtualKey: m.tCode, keyDown: type == .keyDown) {
                    e.flags = CGEventFlags(rawValue: m.tFlags)
                    e.setIntegerValueField(.eventSourceUserData, value: 12345)
                    e.tapPostEvent(proxy)
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
