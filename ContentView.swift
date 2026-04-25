import SwiftUI
import AppKit

enum SidebarItem: String, CaseIterable {
    case rules = "rules"
    case blacklist = "blacklist"
    case settings = "settings"
    case about = "about"
    
    var title: String {
        switch self {
        case .rules: return NSLocalizedString("sidebar.rules", comment: "")
        case .blacklist: return NSLocalizedString("sidebar.blacklist", comment: "")
        case .settings: return NSLocalizedString("sidebar.settings", comment: "")
        case .about: return NSLocalizedString("sidebar.about", comment: "")
        }
    }
    
    var icon: String {
        switch self {
        case .rules: return "keyboard"
        case .blacklist: return "xmark.circle"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

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
        .onAppear {
            if let window = NSApplication.shared.windows.first(where: { $0.contentView != nil && !$0.isSheet }) {
                window.isReleasedWhenClosed = false
                AppDelegate.instance.setMainWindow(window)
                
                if !engine.isActive {
                    window.level = .floating
                }
            }
        }
        .onChange(of: engine.isActive) { isActive in
            if let window = NSApplication.shared.windows.first(where: { $0.contentView != nil && !$0.isSheet }) {
                if isActive {
                    window.level = .normal
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                } else {
                    window.level = .floating
                }
            }
        }
    }
}

struct SidebarView: View {
    @Binding var selectedTab: SidebarItem
    @StateObject var engine = MyEngine.shared
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    SidebarButton(item: item, selectedTab: $selectedTab, count: item == .blacklist ? engine.blacklist.count : nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            Spacer()
            
            VStack(spacing: 0) {
                Divider()
                
                VStack(spacing: 12) {
                    HStack {
                        Text(engine.isActive ? (engine.isPaused ? NSLocalizedString("sidebar.engine.paused", comment: "") : NSLocalizedString("sidebar.engine.running", comment: "")) : NSLocalizedString("sidebar.engine.waiting", comment: ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(engine.isActive ? (engine.isPaused ? .orange : .green) : .red)
                        
                        Spacer()
                        
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
                        Text(NSLocalizedString("sidebar.auth.restart", comment: ""))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    if let hk = engine.pauseHotkey {
                        VStack(spacing: 2) {
                            Text(String(format: NSLocalizedString("sidebar.pause.hint", comment: ""), MyMap.getName(hk.0, hk.1)))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Text(formatDate())
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(12)
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 200)
    }
    
    private func formatDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: Date())
    }
}

struct SidebarButton: View {
    let item: SidebarItem
    @Binding var selectedTab: SidebarItem
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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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

struct DetailView: View {
    let selectedTab: SidebarItem
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(selectedTab.title)
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            Group {
                switch selectedTab {
                case .rules:
                    RulesView()
                case .blacklist:
                    BlacklistView()
                case .settings:
                    SettingsView()
                case .about:
                    AboutView()
                }
            }
        }
    }
}
