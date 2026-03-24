import SwiftUI
import AppKit

struct KeyLogic: NSViewRepresentable {
    @Binding var r1: Bool
    @Binding var r2: Bool
    @Binding var t1: (UInt16, UInt64)?
    @Binding var t2: (UInt16, UInt64)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(r1: $r1, r2: $r2, t1: $t1, t2: $t2)
    }
    
    func makeNSView(context: Context) -> NSView {
        let kv = KV(coordinator: context.coordinator)
        return kv
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    class Coordinator: NSObject {
        @Binding var r1: Bool
        @Binding var r2: Bool
        @Binding var t1: (UInt16, UInt64)?
        @Binding var t2: (UInt16, UInt64)?
        
        init(r1: Binding<Bool>, r2: Binding<Bool>, t1: Binding<(UInt16, UInt64)?>, t2: Binding<(UInt16, UInt64)?>) {
            _r1 = r1
            _r2 = r2
            _t1 = t1
            _t2 = t2
        }
    }
}

// NSView 子类
class KV: NSView {
    var coordinator: KeyLogic.Coordinator
    
    override var acceptsFirstResponder: Bool { true }
    
    init(coordinator: KeyLogic.Coordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseDown(with event: NSEvent) {
        self.window?.makeFirstResponder(self)
    }
    
    override func keyDown(with e: NSEvent) {
        if coordinator.r1 == true || coordinator.r2 == true {
            let code = UInt16(e.keyCode)
            let flags = UInt64(e.modifierFlags.rawValue)
            
            if coordinator.r1 == true {
                coordinator.t1 = (code, flags)
                coordinator.r1 = false
            } else if coordinator.r2 == true {
                coordinator.t2 = (code, flags)
                coordinator.r2 = false
            }
            return
        }
        super.keyDown(with: e)
    }
}