import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("setting_launch_at_login") private var launchAtLogin = false
    @AppStorage("setting_hide_dock") private var hideDock = false
    @StateObject var engine = MyEngine.shared
    @State private var isRecHotkey = false
    @State private var tmpHotkey: (UInt16, UInt64)? = nil
    @State private var showBlacklist = false

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

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("pause.hotkey", comment: ""))
                            .font(.system(size: 13, weight: .medium))
                        Text(NSLocalizedString("pause.hotkey.desc", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if isRecHotkey {
                        Text(NSLocalizedString("waiting.for.input", comment: ""))
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    } else if let hk = engine.pauseHotkey {
                        Text(MyMap.getName(hk.0, hk.1))
                            .font(.system(size: 12, design: .monospaced))

                        Button(action: {
                            engine.pauseHotkey = (keyCode: 6, flags: 0x120000)
                        }) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: {
                            isRecHotkey = true
                        }) {
                            Text(NSLocalizedString("pause.hotkey.record", comment: ""))
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Divider()
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("app.blacklist", comment: ""))
                            .font(.system(size: 13, weight: .medium))
                        Text(NSLocalizedString("app.blacklist.short.desc", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { showBlacklist = true }) {
                        Text("\(engine.blacklist.count)")
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 5)

            Spacer()
        }
        .padding(20)
        .frame(width: 300, height: 370)
        .background(KeyLogic(r1: $isRecHotkey, r2: .constant(false), t1: $tmpHotkey, t2: .constant(nil)))
        .onChange(of: isRecHotkey) { newValue in
            if !newValue, let hk = tmpHotkey {
                engine.pauseHotkey = hk
                tmpHotkey = nil
            }
        }
        .sheet(isPresented: $showBlacklist) {
            BlacklistView()
        }
    }

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

    private func toggleDockIcon(hide: Bool) {
        let policy: NSApplication.ActivationPolicy = hide ? .accessory : .regular
        NSApplication.shared.setActivationPolicy(policy)

        if let window = NSApplication.shared.windows.first(where: { $0.contentView != nil && !$0.isSheet }) {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
