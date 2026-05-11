import SwiftUI
import AppKit

// MARK: - SidebarItem
// 侧边栏导航项枚举，定义四个主要页面入口

enum SidebarItem: String, CaseIterable {
    case rules = "rules"
    case blacklist = "blacklist"
    case toast = "toast"
    case settings = "settings"
    case about = "about"

    // 侧边栏项的本地化标题
    var title: String {
        switch self {
        case .rules: return NSLocalizedString("sidebar.rules", comment: "")
        case .blacklist: return NSLocalizedString("sidebar.blacklist", comment: "")
        case .toast: return NSLocalizedString("sidebar.toast", comment: "")
        case .settings: return NSLocalizedString("sidebar.settings", comment: "")
        case .about: return NSLocalizedString("sidebar.about", comment: "")
        }
    }

    // 侧边栏项的 SF Symbol 图标名
    var icon: String {
        switch self {
        case .rules: return "keyboard"
        case .blacklist: return "xmark.circle"
        case .toast: return "text.bubble"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

// MARK: - ContentView
// 主界面布局，使用 NavigationSplitView 构建侧边栏 + 详情页结构。
// 侧边栏显示导航按钮、引擎运行状态及暂停开关；
// 详情页根据选中项切换 RulesView / BlacklistView / SettingsView / AboutView。

struct ContentView: View {
    @StateObject var engine = MyEngine.shared
    @State private var selectedTab: SidebarItem = .rules

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTab: $selectedTab)
        } detail: {
            DetailView(selectedTab: selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - SidebarView
// 侧边栏视图，包含导航按钮列表和底部引擎状态面板

struct SidebarView: View {
    @Binding var selectedTab: SidebarItem
    @StateObject var engine = MyEngine.shared

    var body: some View {
        VStack(spacing: 0) {
            // 导航按钮区域
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    SidebarButton(item: item, selectedTab: $selectedTab, count: item == .blacklist ? engine.blacklist.count : nil)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)

            Spacer()

            // 底部引擎状态面板
            VStack(spacing: 0) {
                Divider()

                VStack(spacing: 12) {
                    HStack {
                        // 引擎状态文字：运行中(绿) / 已暂停(橙) / 等待授权(红，可点击跳转设置)
                        if engine.isActive {
                            Text(engine.isPaused ? NSLocalizedString("sidebar.engine.paused", comment: "") : NSLocalizedString("sidebar.engine.running", comment: ""))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(engine.isPaused ? .orange : .green)
                        } else {
                            Text(NSLocalizedString("sidebar.engine.waiting", comment: ""))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.red)
                        }

                        Spacer()

                        // 引擎暂停/恢复开关（仅引擎激活时显示）
                        if engine.isActive {
                            Toggle("", isOn: Binding(
                                get: { !engine.isPaused },
                                set: { engine.isPaused = !$0 }
                            ))
                            .toggleStyle(.switch)
                            .scaleEffect(0.6)
                            .labelsHidden()
                        }
                    }

                    if !engine.isActive {
                        Button(action: { selectedTab = .settings }) {
                            Text(NSLocalizedString("sidebar.go.to.settings", comment: ""))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.accentColor)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    // 暂停热键提示和当前日期
                    if let hk = engine.pauseHotkey {
                        VStack(spacing: 2) {
                            Text(String(format: NSLocalizedString("sidebar.pause.hint", comment: ""), MyMap.getName(hk.0, hk.1)))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            Text(Date().formattedMedium)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(12)
            }
        }
        .frame(minWidth: 200)
    }
}

// MARK: - SidebarButton
// 侧边栏导航按钮组件，支持选中高亮、悬停效果和计数徽标

struct SidebarButton: View {
    let item: SidebarItem
    @Binding var selectedTab: SidebarItem
    // 右侧计数徽标（如黑名单数量），nil 时不显示
    let count: Int?

    @State private var isHovered = false

    var body: some View {
        Button(action: { selectedTab = item }) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 14))
                    .frame(width: 18)

                Text(item.title)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                // 计数徽标
                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedTab == item ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.1) : Color.clear))
            )
            .foregroundColor(selectedTab == item ? .white : .primary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - DetailView
// 详情页视图，根据选中的侧边栏项切换对应的子视图

struct DetailView: View {
    let selectedTab: SidebarItem

    var body: some View {
        VStack(spacing: 0) {
            // 页面标题栏
            HStack {
                Text(selectedTab.title)
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 根据 selectedTab 切换子视图
            Group {
                switch selectedTab {
                case .rules:
                    RulesView()
                case .blacklist:
                    BlacklistView()
                case .toast:
                    ToastSettingsView()
                case .settings:
                    SettingsView()
                case .about:
                    AboutView()
                }
            }
        }
    }
}
