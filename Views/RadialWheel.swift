import SwiftUI
import Combine
import AppKit

class RadialWheelState: ObservableObject {
    @Published var selectedIndex: Int? = nil
    @Published var isVisible: Bool = false
}

class RadialWheelManager {
    static let shared = RadialWheelManager()

    private var window: NSPanel?
    private var hostingView: NSHostingView<RadialWheelHostingView>?
    private var mappings: [MyMap] = []
    private var mouseMonitor: Any? = nil
    private var wheelCenter: NSPoint = .zero
    private let state = RadialWheelState()
    var onCancelled: (() -> Void)?

    let outerRadius: CGFloat = 70
    let innerRadius: CGFloat = 16

    func show(mappings: [MyMap], at point: NSPoint) {
        guard mappings.count > 1 else { return }
        hide()

        self.mappings = mappings
        self.wheelCenter = point
        state.selectedIndex = nil
        state.isVisible = false

        let view = RadialWheelHostingView(
            mappings: mappings,
            state: state,
            outerRadius: outerRadius,
            innerRadius: innerRadius
        )

        let size = outerRadius * 2 + 40
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: size, height: size)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        self.hostingView = hosting

        var origin = NSPoint(
            x: point.x - size / 2,
            y: point.y - size / 2
        )

        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            origin.x = max(sf.minX, min(origin.x, sf.maxX - size))
            origin.y = max(sf.minY, min(origin.y, sf.maxY - size))
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: size, height: size)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating + 1
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        self.window = panel
        panel.orderFrontRegardless()

        DispatchQueue.main.async {
            self.state.isVisible = true
        }

        startMouseTracking()
    }

    func hide() {
        stopMouseTracking()
        window?.orderOut(nil)
        window = nil
        hostingView = nil
        mappings = []
        state.selectedIndex = nil
        state.isVisible = false
    }

    func cancel() {
        hide()
        onCancelled?()
        onCancelled = nil
    }

    func getSelectedMapping() -> MyMap? {
        if let idx = state.selectedIndex, idx < mappings.count {
            return mappings[idx]
        }
        return mappings.first
    }

    private func startMouseTracking() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] _ in
            self?.updateSelection()
        }
    }

    private func stopMouseTracking() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    private func updateSelection() {
        let mouseLocation = NSEvent.mouseLocation
        let dx = mouseLocation.x - wheelCenter.x
        let dy = mouseLocation.y - wheelCenter.y
        let distance = sqrt(dx * dx + dy * dy)

        if distance > outerRadius || distance < innerRadius {
            state.selectedIndex = nil
        } else {
            var angle = atan2(dx, dy) * 180 / .pi
            if angle < 0 { angle += 360 }

            let segmentAngle = 360.0 / Double(mappings.count)
            let index = Int(angle / segmentAngle) % mappings.count
            state.selectedIndex = index
        }
    }
}

struct RadialWheelHostingView: View {
    let mappings: [MyMap]
    @ObservedObject var state: RadialWheelState
    let outerRadius: CGFloat
    let innerRadius: CGFloat

    var body: some View {
        RadialWheelView(
            mappings: mappings,
            selectedIndex: state.selectedIndex,
            isVisible: state.isVisible,
            outerRadius: outerRadius,
            innerRadius: innerRadius
        )
        .frame(width: outerRadius * 2 + 40, height: outerRadius * 2 + 40)
    }
}

struct RadialWheelView: View {
    let mappings: [MyMap]
    let selectedIndex: Int?
    let isVisible: Bool
    let outerRadius: CGFloat
    let innerRadius: CGFloat

    private var segmentAngle: Double {
        360.0 / Double(mappings.count)
    }

    private var viewCenter: CGPoint {
        CGPoint(x: outerRadius + 20, y: outerRadius + 20)
    }

    var body: some View {
        ZStack {
            outerRingBackground

            ForEach(0..<mappings.count, id: \.self) { i in
                segmentBackground(index: i)
            }

            ForEach(0..<mappings.count, id: \.self) { i in
                segmentHighlight(index: i)
            }

            ForEach(0..<mappings.count, id: \.self) { i in
                dividerLine(index: i)
            }

            ForEach(0..<mappings.count, id: \.self) { i in
                segmentLabel(index: i)
            }

            innerCircle
        }
        .frame(width: outerRadius * 2 + 40, height: outerRadius * 2 + 40)
        .applyWheelGlassEffect(outerRadius: outerRadius)
        .scaleEffect(isVisible ? 1 : 0.01)
        .opacity(isVisible ? 1 : 0)
        .animation(.spring(response: 0.1, dampingFraction: 0.8, blendDuration: 0), value: isVisible)
    }

    private var outerRingBackground: some View {
        Circle()
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.4),
                        Color.white.opacity(0.1),
                        Color.white.opacity(0.05),
                        Color.white.opacity(0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 2
            )
            .frame(width: outerRadius * 2, height: outerRadius * 2)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: outerRadius * 2, height: outerRadius * 2)
            )
            .position(viewCenter)
    }

    private func donutSegment(index: Int) -> some Shape {
        let startDeg = -90 + segmentAngle * Double(index)
        let endDeg = -90 + segmentAngle * Double(index + 1)

        return Path { path in
            path.addArc(
                center: viewCenter,
                radius: outerRadius - 2,
                startAngle: .degrees(startDeg),
                endAngle: .degrees(endDeg),
                clockwise: false
            )
            path.addArc(
                center: viewCenter,
                radius: innerRadius + 2,
                startAngle: .degrees(endDeg),
                endAngle: .degrees(startDeg),
                clockwise: true
            )
            path.closeSubpath()
        }
    }

    private func segmentBackground(index: Int) -> some View {
        donutSegment(index: index)
            .fill(Color.clear)
    }

    private func segmentHighlight(index: Int) -> some View {
        donutSegment(index: index)
            .fill(selectedIndex == index ? Color.white.opacity(0.2) : Color.clear)
    }

    private func dividerLine(index: Int) -> some View {
        let angle = -90 + segmentAngle * Double(index)
        let rad = angle * .pi / 180

        return Path { path in
            path.move(to: CGPoint(
                x: viewCenter.x + (innerRadius + 2) * cos(rad),
                y: viewCenter.y + (innerRadius + 2) * sin(rad)
            ))
            path.addLine(to: CGPoint(
                x: viewCenter.x + (outerRadius - 2) * cos(rad),
                y: viewCenter.y + (outerRadius - 2) * sin(rad)
            ))
        }
        .stroke(Color.white.opacity(0.25), lineWidth: 1)
    }

    private func segmentLabel(index: Int) -> some View {
        let midAngle = -90 + segmentAngle * Double(index) + segmentAngle / 2
        let labelRadius = (outerRadius + innerRadius) / 2
        let rad = midAngle * .pi / 180
        let labelPos = CGPoint(
            x: viewCenter.x + labelRadius * cos(rad),
            y: viewCenter.y + labelRadius * sin(rad)
        )

        let isSelected = selectedIndex == index
        let name = MyMap.getName(mappings[index].tCode, mappings[index].tFlags)

        return Text(name.trimmingCharacters(in: .whitespaces))
            .font(.system(size: fontSize, weight: isSelected ? .bold : .medium, design: .rounded))
            .foregroundColor(isSelected ? .white : .white.opacity(0.9))
            .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
            .position(labelPos)
    }

    private var innerCircle: some View {
        Circle()
            .fill(Color.white.opacity(0.2))
            .frame(width: innerRadius * 2 - 4, height: innerRadius * 2 - 4)
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .frame(width: innerRadius * 2 - 4, height: innerRadius * 2 - 4)
            )
            .position(viewCenter)
    }

    private var fontSize: CGFloat {
        switch mappings.count {
        case 2: return 14
        case 3: return 13
        case 4: return 12
        default: return 11
        }
    }
}

extension View {
    @ViewBuilder
    func applyWheelGlassEffect(outerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.clear.interactive(), in: .circle)
        } else {
            self.background(
                Circle()
                    .fill(.ultraThinMaterial.opacity(0.6))
                    .frame(width: outerRadius * 2, height: outerRadius * 2),
                alignment: .center
            )
        }
    }
}
