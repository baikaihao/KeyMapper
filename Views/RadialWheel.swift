import SwiftUI
import Combine
import AppKit

// MARK: - RadialWheelState
// 径向轮盘的响应式状态，管理选中索引和可见性

class RadialWheelState: ObservableObject {
    // 当前鼠标悬停选中的扇区索引，nil 表示无选中
    @Published var selectedIndex: Int? = nil
    // 轮盘是否可见（用于控制出现/消失动画）
    @Published var isVisible: Bool = false
}

// MARK: - RadialWheelManager
// 多映射径向选择轮盘管理器（单例）。
// 当同一按键映射到多个目标时，在鼠标位置弹出径向轮盘供用户选择。
//
// 工作流程：
// 1. show() 创建 NSPanel 浮窗并显示轮盘
// 2. startMouseTracking() 监听全局鼠标移动事件
// 3. updateSelection() 根据鼠标位置计算当前选中的扇区
// 4. getSelectedMapping() 返回用户选中的映射规则
// 5. hide() 关闭浮窗并停止鼠标追踪

class RadialWheelManager {
    static let shared = RadialWheelManager()

    // NSPanel 浮窗引用
    private var window: NSPanel?
    // SwiftUI 承载视图
    private var hostingView: NSHostingView<RadialWheelHostingView>?
    // 当前轮盘展示的映射规则列表
    private var mappings: [MyMap] = []
    // 全局鼠标移动事件监听器
    private var mouseMonitor: Any? = nil
    // 轮盘中心点坐标（屏幕坐标系）
    private var wheelCenter: NSPoint = .zero
    // 轮盘响应式状态
    private let state = RadialWheelState()
    // 取消回调
    var onCancelled: (() -> Void)?

    // 轮盘外圈半径
    let outerRadius: CGFloat = 70
    // 轮盘内圈半径
    let innerRadius: CGFloat = 16

    // MARK: - 显示/隐藏

    // 在指定位置显示径向轮盘。
    // 创建一个无边框、透明背景、浮层级别的 NSPanel，
    // 内嵌 SwiftUI 视图绘制环形菜单。
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

        // 计算浮窗位置，确保不超出屏幕可见区域
        var origin = NSPoint(
            x: point.x - size / 2,
            y: point.y - size / 2
        )

        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            origin.x = max(sf.minX, min(origin.x, sf.maxX - size))
            origin.y = max(sf.minY, min(origin.y, sf.maxY - size))
        }

        // 创建无边框透明浮窗
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: size, height: size)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // 浮层级别高于普通窗口，确保轮盘始终可见
        panel.level = .floating + 1
        // 忽略鼠标事件，让鼠标穿透到下方的应用
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        self.window = panel
        panel.orderFrontRegardless()

        // 延迟一帧设置可见状态，触发出现动画
        DispatchQueue.main.async {
            self.state.isVisible = true
        }

        startMouseTracking()
    }

    // 隐藏轮盘并清理资源
    func hide() {
        stopMouseTracking()
        window?.orderOut(nil)
        window = nil
        hostingView = nil
        mappings = []
        state.selectedIndex = nil
        state.isVisible = false
    }

    // 取消轮盘选择，触发取消回调
    func cancel() {
        hide()
        onCancelled?()
        onCancelled = nil
    }

    // 获取用户当前选中的映射规则。
    // 如果有选中索引则返回对应映射，否则返回第一个映射作为默认值。
    func getSelectedMapping() -> MyMap? {
        if let idx = state.selectedIndex, idx < mappings.count {
            return mappings[idx]
        }
        return mappings.first
    }

    // MARK: - 鼠标追踪

    // 开始监听全局鼠标移动事件，用于实时更新轮盘选中扇区
    private func startMouseTracking() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] _ in
            self?.updateSelection()
        }
    }

    // 停止鼠标移动事件监听
    private func stopMouseTracking() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    // 根据当前鼠标位置计算选中的扇区索引。
    // 算法：
    // 1. 计算鼠标到轮盘中心的距离
    // 2. 距离不在 [innerRadius, outerRadius] 范围内则取消选中
    // 3. 在范围内时，用 atan2 计算角度，转换为扇区索引
    private func updateSelection() {
        let mouseLocation = NSEvent.mouseLocation
        let dx = mouseLocation.x - wheelCenter.x
        let dy = mouseLocation.y - wheelCenter.y
        let distance = sqrt(dx * dx + dy * dy)

        if distance > outerRadius || distance < innerRadius {
            state.selectedIndex = nil
        } else {
            // atan2(dx, dy) 以正上方为 0°，顺时针增加
            var angle = atan2(dx, dy) * 180 / .pi
            if angle < 0 { angle += 360 }

            let segmentAngle = 360.0 / Double(mappings.count)
            let index = Int(angle / segmentAngle) % mappings.count
            state.selectedIndex = index
        }
    }
}

// MARK: - RadialWheelHostingView
// 径向轮盘的 SwiftUI 承载视图，将状态传递给实际绘制视图

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

// MARK: - RadialWheelView
// 径向轮盘的 SwiftUI 绘制视图。
// 绘制一个环形菜单，每个扇区代表一个映射目标，鼠标悬停时高亮选中扇区。
// 支持 macOS 26+ 的原生 glassEffect，低版本回退为 ultraThinMaterial。

struct RadialWheelView: View {
    let mappings: [MyMap]
    let selectedIndex: Int?
    let isVisible: Bool
    let outerRadius: CGFloat
    let innerRadius: CGFloat

    // 每个扇区的角度（度）
    private var segmentAngle: Double {
        360.0 / Double(mappings.count)
    }

    // 视图中心点坐标
    private var viewCenter: CGPoint {
        CGPoint(x: outerRadius + 20, y: outerRadius + 20)
    }

    var body: some View {
        ZStack {
            // 外圈背景环
            outerRingBackground

            // 扇区背景（透明，仅占位）
            ForEach(0..<mappings.count, id: \.self) { i in
                segmentBackground(index: i)
            }

            // 扇区高亮（选中时半透明白色填充）
            ForEach(0..<mappings.count, id: \.self) { i in
                segmentHighlight(index: i)
            }

            // 扇区分割线
            ForEach(0..<mappings.count, id: \.self) { i in
                dividerLine(index: i)
            }

            // 扇区标签（映射目标按键名称）
            ForEach(0..<mappings.count, id: \.self) { i in
                segmentLabel(index: i)
            }

            // 中心圆
            innerCircle
        }
        .frame(width: outerRadius * 2 + 40, height: outerRadius * 2 + 40)
        .applyWheelGlassEffect(outerRadius: outerRadius)
        // 出现/消失动画
        .scaleEffect(isVisible ? 1 : 0.01)
        .opacity(isVisible ? 1 : 0)
        .animation(.spring(response: 0.1, dampingFraction: 0.8, blendDuration: 0), value: isVisible)
    }

    // MARK: - 绘制组件

    // 外圈背景环：带渐变描边的半透明圆
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

    // 生成环形扇区路径（donut segment）
    // 从 -90° 开始（正上方），顺时针绘制
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

    // 扇区背景（透明占位）
    private func segmentBackground(index: Int) -> some View {
        donutSegment(index: index)
            .fill(Color.clear)
    }

    // 扇区高亮：选中时填充半透明白色
    private func segmentHighlight(index: Int) -> some View {
        donutSegment(index: index)
            .fill(selectedIndex == index ? Color.white.opacity(0.2) : Color.clear)
    }

    // 扇区分割线：从内圈到外圈的径向线段
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

    // 扇区标签：在扇区中心位置显示映射目标按键名称
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

    // 中心圆：带渐变描边的半透明圆
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

    // 根据映射数量动态调整字体大小，确保文字不超出扇区
    private var fontSize: CGFloat {
        switch mappings.count {
        case 2: return 14
        case 3: return 13
        case 4: return 12
        default: return 11
        }
    }
}

// MARK: - View 扩展：毛玻璃效果

extension View {
    // 为径向轮盘应用毛玻璃背景效果。
    // macOS 26+ 使用原生 glassEffect，低版本回退为 ultraThinMaterial。
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
