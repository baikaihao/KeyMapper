import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("setting_launch_at_login") private var launchAtLogin = false
    @AppStorage("setting_hide_dock") private var hideDock = false
    @StateObject var engine = MyEngine.shared
    @StateObject var backupManager = BackupManager.shared
    @State private var isRecHotkey = false
    @State private var tmpHotkey: (UInt16, UInt64)? = nil
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(NSLocalizedString("settings.general", comment: ""))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 12)
                    
                    VStack(spacing: 0) {
                        SettingsRow(
                            title: NSLocalizedString("settings.launch.at.login", comment: ""),
                            description: NSLocalizedString("settings.launch.at.login.desc", comment: "")
                        ) {
                            Toggle("", isOn: $launchAtLogin)
                                .toggleStyle(.switch)
                                .onChange(of: launchAtLogin) { newValue in
                                    toggleLaunchAtLogin(enabled: newValue)
                                }
                        }
                        
                        Divider()
                            .padding(.leading, 0)
                        
                        SettingsRow(
                            title: NSLocalizedString("settings.hide.dock.icon", comment: ""),
                            description: NSLocalizedString("settings.hide.dock.icon.desc", comment: "")
                        ) {
                            Toggle("", isOn: $hideDock)
                                .toggleStyle(.switch)
                                .onChange(of: hideDock) { newValue in
                                    toggleDockIcon(hide: newValue)
                                }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(NSLocalizedString("settings.mapping", comment: ""))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 12)
                    
                    VStack(spacing: 0) {
                        SettingsRow(
                            title: NSLocalizedString("settings.pause.hotkey", comment: ""),
                            description: NSLocalizedString("settings.pause.hotkey.desc", comment: "")
                        ) {
                            HStack(spacing: 8) {
                                if isRecHotkey {
                                    Text(NSLocalizedString("settings.waiting.input", comment: ""))
                                        .font(.system(size: 12))
                                        .foregroundColor(.orange)
                                } else if let hk = engine.pauseHotkey {
                                    Text(MyMap.getName(hk.0, hk.1))
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(.accentColor)
                                    
                                    Button(action: {
                                        engine.pauseHotkey = (keyCode: 6, flags: 0x120000)
                                    }) {
                                        Image(systemName: "arrow.counterclockwise.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Button(action: {
                                        isRecHotkey = true
                                    }) {
                                        Text(NSLocalizedString("settings.record", comment: ""))
                                            .font(.system(size: 11))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        Divider()
                            .padding(.leading, 0)
                        
                        SettingsRow(
                            title: NSLocalizedString("settings.accessibility", comment: ""),
                            description: NSLocalizedString("settings.accessibility.desc", comment: "")
                        ) {
                            if engine.isActive {
                                Label(NSLocalizedString("settings.authorized", comment: ""), systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                            } else {
                                Button(NSLocalizedString("settings.enable", comment: "")) {
                                    requestAccessibilityPermission()
                                }
                                .font(.system(size: 11))
                            }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(NSLocalizedString("settings.data", comment: ""))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 12)
                    
                    HStack(spacing: 12) {
                        Button(action: exportConfig) {
                            Label(NSLocalizedString("settings.export.rules", comment: ""), systemImage: "arrow.down.circle")
                                .font(.system(size: 13, weight: .medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: importConfig) {
                            Label(NSLocalizedString("settings.import", comment: ""), systemImage: "arrow.up.circle")
                                .font(.system(size: 13, weight: .medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(NSLocalizedString("settings.auto.backup", comment: ""))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 12)
                    
                    VStack(spacing: 0) {
                        SettingsRow(
                            title: NSLocalizedString("settings.auto.backup.enable", comment: ""),
                            description: NSLocalizedString("settings.auto.backup.enable.desc", comment: "")
                        ) {
                            Toggle("", isOn: $backupManager.autoBackupEnabled)
                                .toggleStyle(.switch)
                        }
                        
                        Divider()
                            .padding(.leading, 0)
                        
                        SettingsRow(
                            title: NSLocalizedString("settings.backup.interval", comment: ""),
                            description: NSLocalizedString("settings.backup.interval.desc", comment: "")
                        ) {
                            Picker("", selection: $backupManager.backupIntervalDays) {
                                ForEach(1...14, id: \.self) { day in
                                    Text("\(day) \(NSLocalizedString("settings.days", comment: ""))").tag(day)
                                }
                            }
                            .frame(width: 100)
                            .disabled(!backupManager.autoBackupEnabled)
                        }
                        
                        Divider()
                            .padding(.leading, 0)
                        
                        SettingsRow(
                            title: NSLocalizedString("settings.max.backups", comment: ""),
                            description: NSLocalizedString("settings.max.backups.desc", comment: "")
                        ) {
                            Picker("", selection: $backupManager.maxBackupCount) {
                                ForEach(1...20, id: \.self) { count in
                                    Text("\(count)").tag(count)
                                }
                            }
                            .frame(width: 80)
                        }
                        
                        Divider()
                            .padding(.leading, 0)
                        
                        SettingsRow(
                            title: NSLocalizedString("settings.backup.path", comment: ""),
                            description: backupManager.backupPath
                        ) {
                            HStack(spacing: 8) {
                                Button(action: {
                                    backupManager.openBackupFolder()
                                }) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .help(NSLocalizedString("settings.open.folder", comment: ""))
                                
                                Button(action: {
                                    if let newPath = backupManager.selectBackupFolder() {
                                        backupManager.backupPath = newPath
                                    }
                                }) {
                                    Text(NSLocalizedString("settings.select", comment: ""))
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        
                        Divider()
                            .padding(.leading, 0)
                        
                        SettingsRow(
                            title: NSLocalizedString("settings.last.backup", comment: ""),
                            description: backupManager.lastBackupDate != nil 
                                ? formatDate(backupManager.lastBackupDate!) 
                                : NSLocalizedString("settings.never", comment: "")
                        ) {
                            Button(action: {
                                backupManager.performBackup()
                            }) {
                                Text(NSLocalizedString("settings.backup.now", comment: ""))
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            .padding(20)
        }
        .background(KeyLogic(r1: $isRecHotkey, r2: .constant(false), t1: $tmpHotkey, t2: .constant(nil)))
        .onChange(of: isRecHotkey) { newValue in
            if !newValue, let hk = tmpHotkey {
                engine.pauseHotkey = hk
                tmpHotkey = nil
            }
        }
    }
    
    private func toggleLaunchAtLogin(enabled: Bool) {
        let service = SMAppService.mainApp

        if enabled {
            do {
                try service.register()
            } catch {
                DispatchQueue.main.async {
                    self.launchAtLogin = false
                }
                showLaunchError()
            }
        } else {
            service.unregister { error in
                if let error = error {
                    print("Failed to unregister: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showLaunchError() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("settings.launch.error.title", comment: "")
        alert.informativeText = NSLocalizedString("settings.launch.error.message", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("ok", comment: ""))
        alert.runModal()
    }
    
    private func toggleDockIcon(hide: Bool) {
        NSApp.setActivationPolicy(hide ? .accessory : .regular)

        if !hide {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.contentView != nil && !$0.isSheet && !($0 is NSPanel) }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "keymapper_rules.json"
        panel.message = NSLocalizedString("settings.export.message", comment: "")
        panel.directoryURL = URL(fileURLWithPath: backupManager.backupPath)
        
        if panel.runModal() == .OK, let url = panel.url {
            let config: [String: Any] = [
                "version": "2.0",
                "mappings": engine.list.map { [
                    "id": $0.id.uuidString,
                    "fCode": $0.fCode,
                    "fFlags": $0.fFlags,
                    "tCode": $0.tCode,
                    "tFlags": $0.tFlags,
                    "isOn": $0.isOn,
                    "note": $0.note
                ]},
                "blacklist": engine.blacklist,
                "pauseHotkey": engine.pauseHotkey.map { [
                    "keyCode": $0.keyCode,
                    "flags": $0.flags
                ]} as Any
            ]
            
            do {
                let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
                try data.write(to: url)
                showAlert(
                    title: NSLocalizedString("settings.export.success.title", comment: ""),
                    message: NSLocalizedString("settings.export.success.message", comment: ""),
                    style: .informational
                )
            } catch {
                showAlert(
                    title: NSLocalizedString("settings.export.error.title", comment: ""),
                    message: error.localizedDescription,
                    style: .critical
                )
            }
        }
    }
    
    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = NSLocalizedString("settings.import.message", comment: "")
        panel.directoryURL = URL(fileURLWithPath: backupManager.backupPath)
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                guard let config = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw NSError(domain: "KeyMapper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
                }
                
                var importedCount = 0
                
                if let mappings = config["mappings"] as? [[String: Any]] {
                    let newMappings = mappings.compactMap { m -> MyMap? in
                        guard let fCode = m["fCode"] as? UInt16,
                              let fFlags = m["fFlags"] as? UInt64,
                              let tCode = m["tCode"] as? UInt16,
                              let tFlags = m["tFlags"] as? UInt64 else { return nil }
                        let id = (m["id"] as? String).flatMap { UUID(uuidString: $0) } ?? UUID()
                        let isOn = m["isOn"] as? Bool ?? true
                        let note = m["note"] as? String ?? ""
                        importedCount += 1
                        return MyMap(id: id, fCode: fCode, fFlags: fFlags, tCode: tCode, tFlags: tFlags, isOn: isOn, note: note)
                    }
                    engine.list = newMappings
                }
                
                if let blacklist = config["blacklist"] as? [String] {
                    engine.blacklist = blacklist
                }
                
                if let hotkey = config["pauseHotkey"] as? [String: Any],
                   let keyCode = hotkey["keyCode"] as? UInt16,
                   let flags = hotkey["flags"] as? UInt64 {
                    engine.pauseHotkey = (keyCode: keyCode, flags: flags)
                }
                
                showAlert(
                    title: NSLocalizedString("settings.import.success.title", comment: ""),
                    message: String(format: NSLocalizedString("settings.import.success.message", comment: ""), importedCount),
                    style: .informational
                )
            } catch {
                showAlert(
                    title: NSLocalizedString("settings.import.error.title", comment: ""),
                    message: error.localizedDescription,
                    style: .critical
                )
            }
        }
    }
    
    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: NSLocalizedString("ok", comment: ""))
        alert.runModal()
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder let content: Content
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            content
        }
        .padding(12)
    }
}
