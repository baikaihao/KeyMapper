import SwiftUI
import Combine
import AppKit

class MyEngine: ObservableObject {
    static let shared = MyEngine()
    @Published var list: [MyMap] = [] { didSet { save() } }
    @Published var isActive: Bool = false
    
    private var tap: CFMachPort?
    private var retryTimer: Timer?
    
    init() {
        load()
        start()
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
    
    func start() {
        retryTimer?.invalidate()
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { (proxy, type, event, _) -> Unmanaged<CGEvent>? in
            let c = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let f = event.flags.rawValue
            
            if event.getIntegerValueField(.eventSourceUserData) == 12345 {
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