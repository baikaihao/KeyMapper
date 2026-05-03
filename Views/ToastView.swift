import SwiftUI
import AppKit
import Combine

struct ToastContainerView: View {
    @ObservedObject var state: ToastState

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(state.items) { item in
                ToastItemView(item: item, style: state.style)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }
}

struct ToastItemView: View {
    @ObservedObject var item: ToastItem
    let style: ToastStyle

    var body: some View {
        Text(item.text)
            .font(.system(size: style.fontSize))
            .foregroundColor(style.textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(style.bgColor)
            .cornerRadius(style.cornerRadius)
            .opacity(item.isFading ? 0 : 1)
    }
}

class PositionedColorWell: NSColorWell {
    override func activate(_ exclusive: Bool) {
        let mouseLoc = NSEvent.mouseLocation
        let panel = NSColorPanel.shared
        let panelSize = panel.frame.size
        let screen = NSScreen.screens.first {
            NSPointInRect(mouseLoc, $0.frame)
        } ?? NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let x = min(mouseLoc.x, screenFrame.maxX - panelSize.width)
        let y = max(mouseLoc.y - panelSize.height, screenFrame.origin.y)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        super.activate(exclusive)
    }
}

struct PositionedColorPicker: NSViewRepresentable {
    @Binding var color: Color

    func makeNSView(context: Context) -> PositionedColorWell {
        let well = PositionedColorWell(frame: NSRect(x: 0, y: 0, width: 32, height: 24))
        well.isBordered = true
        well.color = NSColor(color)
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        return well
    }

    func updateNSView(_ nsView: PositionedColorWell, context: Context) {
        let nsColor = NSColor(color)
        if nsView.color != nsColor {
            nsView.color = nsColor
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(color: $color) }

    class Coordinator {
        var color: Binding<Color>
        init(color: Binding<Color>) { self.color = color }

        @objc func colorChanged(_ sender: PositionedColorWell) {
            color.wrappedValue = Color(nsColor: sender.color)
        }
    }
}
