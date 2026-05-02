import SwiftUI
import AppKit

// MARK: - KeyLogic
// 按键录制 NSView 桥接组件。
// 实现 NSViewRepresentable 协议，将 AppKit 的 NSView 子类嵌入 SwiftUI 视图。
// 当用户处于录制模式时，捕获按键的 keyCode 和 modifierFlags 并回传给 SwiftUI 绑定变量。
//
// 工作原理：
// 1. SwiftUI 视图将录制状态（r1/r2）和存储变量（t1/t2）绑定到 KeyLogic
// 2. KeyLogic 创建 Coordinator 作为 SwiftUI ↔ AppKit 的通信桥梁
// 3. KV（NSView 子类）在 keyDown 事件中检查录制状态，将按键数据写入绑定变量
// 4. 录制完成后自动退出录制模式并释放第一响应者
//
// 兼容性修复：
// - 录制开始时主动获取第一响应者状态，确保键盘事件路由到 KV
// - 重写 performKeyEquivalent 拦截修饰键组合事件，防止系统蜂鸣
// - 重写 doCommandBySelector 拦截按键绑定命令，防止系统蜂鸣
// - keyDown 中永不调用 super，避免 interpretKeyEvents → NSBeep 链路

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

    // 当录制状态变化时，主动将 KV 设为第一响应者以确保能接收键盘事件
    func updateNSView(_ nsView: NSView, context: Context) {
        if let kv = nsView as? KV {
            if (r1 || r2) && kv.window?.firstResponder != kv {
                DispatchQueue.main.async {
                    kv.window?.makeFirstResponder(kv)
                }
            }
        }
    }

    // MARK: - Coordinator

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

// MARK: - KV
// NSView 子类，负责实际的按键捕获。
// 重写 keyDown / performKeyEquivalent / doCommandBySelector 三个方法，
// 确保在录制模式下完整拦截所有键盘事件，防止系统蜂鸣。

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

    // 处理捕获的按键事件：提取 keyCode 和 modifierFlags，写入绑定变量
    private func handleKeyEvent(_ event: NSEvent) {
        let code = UInt16(event.keyCode)
        let flags = UInt64(event.modifierFlags.rawValue)

        if coordinator.r1 == true {
            coordinator.t1 = (code, flags)
            coordinator.r1 = false
        } else if coordinator.r2 == true {
            coordinator.t2 = (code, flags)
            coordinator.r2 = false
        }

        // 录制完成后释放第一响应者，让其他控件恢复正常键盘交互
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(nil)
        }
    }

    // 按键事件处理。
    // 录制模式下捕获按键并吞掉事件；非录制模式下也吞掉事件（KV 是背景视图，不应传递事件），
    // 避免调用 super.keyDown → interpretKeyEvents → doCommandBySelector → NSBeep 链路。
    override func keyDown(with e: NSEvent) {
        if coordinator.r1 == true || coordinator.r2 == true {
            handleKeyEvent(e)
        }
        // 永不调用 super.keyDown(with:)，防止系统蜂鸣
    }

    // 拦截修饰键组合事件（如 ⌘+A、⌃+C 等）。
    // 在旧版 macOS 上，修饰键组合可能通过 performKeyEquivalent 路由而非 keyDown，
    // 未重写此方法会导致系统处理事件并播放蜂鸣声。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if coordinator.r1 == true || coordinator.r2 == true {
            handleKeyEvent(event)
            return true
        }
        return false
    }

    // 拦截按键绑定命令。
    // 当 keyDown 调用 super 时，NSView 的默认实现会调用 interpretKeyEvents，
    // 进而发送 doCommandBySelector: 消息。若选择器未处理，系统播放蜂鸣声。
    // 重写此方法在录制模式下吞掉所有命令，防止蜂鸣。
    override func doCommand(by aSelector: Selector) {
        if coordinator.r1 == true || coordinator.r2 == true {
            return
        }
        super.doCommand(by: aSelector)
    }
}
