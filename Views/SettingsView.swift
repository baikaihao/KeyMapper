import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("setting_launch_at_login") private var launchAtLogin = false
    @AppStorage("setting_hide_dock") private var hideDock = false
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(NSLocalizedString("settings", comment: ""))
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 15) {
                // 开机启动
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("launch.at.login", comment: ""))
                            .font(.system(size: 13, weight: .medium))
                        Text(NSLocalizedString("launch.at.login.desc", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { newValue in
                            toggleLaunchAtLogin(enabled: newValue)
                        }
                }
                
                Divider()
                
                // 隐藏程序坞
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("hide.dock.icon", comment: ""))
                            .font(.system(size: 13, weight: .medium))
                        Text(NSLocalizedString("hide.dock.icon.desc", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $hideDock)
                        .toggleStyle(.switch)
                        .onChange(of: hideDock) { newValue in
                            toggleDockIcon(hide: newValue)
                        }
                }
            }
            .padding(.horizontal, 5)
            
            Spacer()
        }
        .padding(20)
        .frame(width: 300, height: 250)
    }
    
    // 开机启动
    private func toggleLaunchAtLogin(enabled: Bool) {
        let service = SMAppService.mainApp
        
        if enabled {
            do {
                try service.register()
                print("Successfully registered launch service")
            } catch {
                print("Failed to register: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.launchAtLogin = false
                }
            }
        } else {
            service.unregister { error in
                if let error = error {
                    print("Failed to unregister: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // 隐藏程序坞
    private func toggleDockIcon(hide: Bool) {
        let policy: NSApplication.ActivationPolicy = hide ? .accessory : .regular
        NSApplication.shared.setActivationPolicy(policy)
        
        // 确保窗口保持在最前面
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}