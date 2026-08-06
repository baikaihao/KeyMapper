import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - SettingsView
// 设置页面，包含四个设置区块：
// 1. 通用设置——开机自启（SMAppService）、隐藏 Dock 图标
// 2. 映射设置——暂停热键录制/重置、辅助功能权限检查
// 3. 数据管理——导出/导入规则配置（JSON 格式）
// 4. 自动备份——启用/间隔/数量上限/路径/立即备份

struct SettingsView: View {
    @AppStorage("setting_launch_at_login") private var launchAtLogin = false
    @AppStorage("setting_hide_dock") private var hideDock = false
    @StateObject var engine = MyEngine.shared
    @StateObject var backupManager = BackupManager.shared
    // 是否正在录制暂停热键
    @State private var isRecHotkey = false
    // 临时存储录制的暂停热键
    @State private var tmpHotkey: (UInt16, UInt64)? = nil
    // 导入期间禁止重复操作，并向用户显示明确的进行中状态。
    @State private var isImportInProgress = false
    // 失效旧回调，避免离开设置页后继续覆盖用户的新修改。
    @State private var activeImportID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // MARK: 通用设置区块
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

                // MARK: 映射设置区块
                VStack(alignment: .leading, spacing: 0) {
                    Text(NSLocalizedString("settings.mapping", comment: ""))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 12)

                    VStack(spacing: 0) {
                        // 暂停热键设置：支持录制新热键和重置为默认值
                        SettingsRow(
                            title: NSLocalizedString("settings.pause.hotkey", comment: ""),
                            description: NSLocalizedString("settings.pause.hotkey.desc", comment: "")
                        ) {
                            HStack(spacing: 8) {
                                if isRecHotkey {
                                    Text(NSLocalizedString("settings.waiting.input", comment: ""))
                                        .font(.system(size: 12))
                                        .foregroundColor(.orange)

                                    Button(NSLocalizedString("cancel", comment: "")) {
                                        cancelHotkeyRecording()
                                    }
                                    .controlSize(.small)
                                } else {
                                    if let hk = engine.pauseHotkey {
                                        Text(MyMap.getName(hk.0, hk.1))
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundColor(.accentColor)
                                    }

                                    Button(action: startHotkeyRecording) {
                                        Label(
                                            NSLocalizedString(
                                                engine.pauseHotkey == nil
                                                    ? "settings.record"
                                                    : "settings.change.hotkey",
                                                comment: ""
                                            ),
                                            systemImage: engine.pauseHotkey == nil ? "record.circle" : "pencil"
                                        )
                                        .font(.system(size: 11))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button(action: resetPauseHotkey) {
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.system(size: 11))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(isUsingDefaultPauseHotkey)
                                    .help(NSLocalizedString("settings.reset.hotkey", comment: ""))
                                }
                            }
                            .disabled(isImportInProgress)
                        }

                        Divider()
                            .padding(.leading, 0)

                        // 辅助功能权限状态与授权入口
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
                        .background(engine.isActive ? Color.clear : Color.orange.opacity(0.1))
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }

                // MARK: 数据管理区块
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
                        .disabled(isImportInProgress || isRecHotkey)

                        Button(action: importConfig) {
                            HStack(spacing: 6) {
                                Group {
                                    if isImportInProgress {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "arrow.up.circle")
                                    }
                                }
                                .frame(width: 16, height: 16)

                                Text(NSLocalizedString("settings.import", comment: ""))
                            }
                                .font(.system(size: 13, weight: .medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isImportInProgress || isRecHotkey)
                    }
                }

                // MARK: 自动备份区块
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
                                // 在 Finder 中打开备份文件夹
                                Button(action: {
                                    backupManager.openBackupFolder()
                                }) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .help(NSLocalizedString("settings.open.folder", comment: ""))

                                // 选择新的备份文件夹
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
                                ? backupManager.lastBackupDate!.formattedMedium
                                : NSLocalizedString("settings.never", comment: "")
                        ) {
                            Button(action: {
                                backupManager.performBackup()
                            }) {
                                HStack(spacing: 6) {
                                    if backupManager.isBackupInProgress {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "externaldrive.badge.timemachine")
                                    }
                                    Text(NSLocalizedString(
                                        backupManager.isBackupInProgress
                                            ? "settings.backup.in.progress"
                                            : "settings.backup.now",
                                        comment: ""
                                    ))
                                }
                                .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .disabled(backupManager.isBackupInProgress)
                        }

                        if backupManager.autoBackupEnabled, let nextBackupDate = backupManager.nextBackupDate {
                            Divider()
                                .padding(.leading, 0)

                            SettingsRow(
                                title: NSLocalizedString("settings.next.backup", comment: ""),
                                description: nextBackupDate.formattedMedium
                            ) {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let lastBackupError = backupManager.lastBackupError {
                            Divider()
                                .padding(.leading, 0)

                            SettingsRow(
                                title: NSLocalizedString("settings.backup.error", comment: ""),
                                description: lastBackupError
                            ) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .disabled(isImportInProgress)
                }

            }
            .padding(20)
        }
        // 嵌入 KeyLogic 以捕获暂停热键录制
        .background(KeyLogic(r1: $isRecHotkey, r2: .constant(false), t1: $tmpHotkey, t2: .constant(nil)))
        .onChange(of: isRecHotkey) { newValue in
            engine.isRecording = newValue

            // 录制结束后，将捕获的热键设置为暂停热键
            if !newValue, let hk = tmpHotkey {
                engine.pauseHotkey = (hk.0, hk.1 & ModifierKey.allMask)
                tmpHotkey = nil
            }
        }
        .onAppear {
            engine.isRecording = false
            syncLaunchAtLoginState()
        }
        .onDisappear {
            cancelImport()
            cancelHotkeyRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cancelKeyRecording)) { _ in
            cancelHotkeyRecording()
        }
    }

    private var isUsingDefaultPauseHotkey: Bool {
        guard let hotkey = engine.pauseHotkey else { return false }
        return hotkey.keyCode == MappingStore.defaultPauseHotkey.keyCode
            && (hotkey.flags & ModifierKey.allMask) == (MappingStore.defaultPauseHotkey.flags & ModifierKey.allMask)
    }

    private func startHotkeyRecording() {
        tmpHotkey = nil
        engine.isRecording = true
        isRecHotkey = true
    }

    private func cancelHotkeyRecording() {
        tmpHotkey = nil
        isRecHotkey = false
        engine.isRecording = false
    }

    private func resetPauseHotkey() {
        cancelHotkeyRecording()
        engine.pauseHotkey = MappingStore.defaultPauseHotkey
    }

    // MARK: - 通用设置方法

    // 读取系统实际登录项状态，修正 UserDefaults 中的设置值
    // 确保 Toggle 显示的状态与 macOS 系统设置一致
    private func syncLaunchAtLoginState() {
        AppDelegate.syncLaunchAtLoginState()
        let service = SMAppService.mainApp
        let systemEnabled = (service.status == .enabled)
        if launchAtLogin != systemEnabled {
            launchAtLogin = systemEnabled
        }
    }

    // 切换开机自启：使用 SMAppService 注册/注销登录项
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

    // 显示开机自启注册失败的错误提示
    private func showLaunchError() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("settings.launch.error.title", comment: "")
        alert.informativeText = NSLocalizedString("settings.launch.error.message", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("ok", comment: ""))
        alert.runModal()
    }

    // 切换 Dock 图标显示：
    // .accessory: 隐藏 Dock 图标，仅菜单栏
    // .regular: 显示 Dock 图标
    private func toggleDockIcon(hide: Bool) {
        NSApp.setActivationPolicy(hide ? .accessory : .regular)

        if !hide {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.contentView != nil && !$0.isSheet && !($0 is NSPanel) }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    // MARK: - 辅助功能权限

    // 请求辅助功能权限：弹出系统授权对话框并打开系统偏好设置
    private func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: - 导出配置

    // 将当前映射规则和暂停热键导出为 JSON 文件
    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "keymapper_rules.json"
        panel.message = NSLocalizedString("settings.export.message", comment: "")
        panel.directoryURL = URL(fileURLWithPath: backupManager.backupPath)

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let config = MappingStore.makeConfiguration(
                    mappings: engine.list,
                    blacklist: engine.blacklist,
                    pauseHotkey: engine.pauseHotkey
                )
                let data = try MappingStore.encodeValidatedConfiguration(config)
                try data.write(to: url, options: .atomic)
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

    // MARK: - 导入配置

    // 从 JSON 文件导入映射规则和暂停热键，覆盖当前配置
    private func importConfig() {
        guard !isImportInProgress, !isRecHotkey else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = NSLocalizedString("settings.import.message", comment: "")
        panel.directoryURL = URL(fileURLWithPath: backupManager.backupPath)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let importID = UUID()
        activeImportID = importID
        isImportInProgress = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try MappingStore.decodeAndValidateConfiguration(at: url)
            }

            DispatchQueue.main.async { [self] in
                handleValidatedImport(result, importID: importID)
            }
        }
    }

    private func handleValidatedImport(
        _ result: Result<MappingStore.ValidatedConfiguration, Error>,
        importID: UUID
    ) {
        guard activeImportID == importID else { return }

        switch result {
        case .failure(let error):
            finishImport(importID)
            showImportError(error)

        case .success(let config):
            guard confirmImport(mappingCount: config.mappings.count) else {
                finishImport(importID)
                return
            }

            backupManager.performBackupAndReportSuccess { [self] succeeded in
                guard activeImportID == importID else { return }

                guard succeeded else {
                    finishImport(importID)
                    showAlert(
                        title: NSLocalizedString("settings.import.backup.error.title", comment: ""),
                        message: NSLocalizedString("settings.import.backup.error.message", comment: ""),
                        style: .critical
                    )
                    return
                }

                do {
                    // Validation and backup complete before the configuration is persisted
                    // in one transaction and then published to the UI.
                    try engine.applyValidatedConfiguration(config)
                    finishImport(importID)
                    showAlert(
                        title: NSLocalizedString("settings.import.success.title", comment: ""),
                        message: String(
                            format: NSLocalizedString("settings.import.success.message", comment: ""),
                            config.mappings.count
                        ),
                        style: .informational
                    )
                } catch {
                    finishImport(importID)
                    showImportError(error)
                }
            }
        }
    }

    private func finishImport(_ importID: UUID) {
        guard activeImportID == importID else { return }
        activeImportID = nil
        isImportInProgress = false
    }

    private func cancelImport() {
        activeImportID = nil
        isImportInProgress = false
    }

    private func showImportError(_ error: Error) {
        showAlert(
            title: NSLocalizedString("settings.import.error.title", comment: ""),
            message: error.localizedDescription,
            style: .critical
        )
    }

    private func confirmImport(mappingCount: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("settings.import.confirm.title", comment: "")
        alert.informativeText = String(
            format: NSLocalizedString("settings.import.confirm.message", comment: ""),
            mappingCount
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("settings.import.confirm.action", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("cancel", comment: ""))
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - 通用弹窗

    // 显示模态警告/信息弹窗
    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: NSLocalizedString("ok", comment: ""))
        alert.runModal()
    }
}

// MARK: - ToastSettingsView
// 弹窗提示的独立设置子页面。

struct ToastSettingsView: View {
    @State private var toastStyle = ToastManager.shared.style

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    settingsSection(
                        title: NSLocalizedString("toast.content", comment: "")
                    ) {
                        VStack(spacing: 0) {
                            SettingsRow(
                                title: NSLocalizedString("toast.show.from.key", comment: ""),
                                description: NSLocalizedString("toast.show.from.key.desc", comment: "")
                            ) {
                                Toggle("", isOn: $toastStyle.showFromKey)
                                    .toggleStyle(.switch)
                                    .onChange(of: toastStyle.showFromKey) { newValue in updateStyle { $0.showFromKey = newValue } }
                            }

                            Divider()

                            SettingsRow(
                                title: NSLocalizedString("toast.show.arrow", comment: ""),
                                description: NSLocalizedString("toast.show.arrow.desc", comment: "")
                            ) {
                                Toggle("", isOn: $toastStyle.showArrow)
                                    .toggleStyle(.switch)
                                    .onChange(of: toastStyle.showArrow) { newValue in updateStyle { $0.showArrow = newValue } }
                            }

                            Divider()

                            SettingsRow(
                                title: NSLocalizedString("toast.show.to.key", comment: ""),
                                description: NSLocalizedString("toast.show.to.key.desc", comment: "")
                            ) {
                                Toggle("", isOn: $toastStyle.showToKey)
                                    .toggleStyle(.switch)
                                    .onChange(of: toastStyle.showToKey) { newValue in updateStyle { $0.showToKey = newValue } }
                            }

                            Divider()

                            SettingsRow(
                                title: NSLocalizedString("toast.show.note", comment: ""),
                                description: NSLocalizedString("toast.show.note.desc", comment: "")
                            ) {
                                Toggle("", isOn: $toastStyle.showNote)
                                    .toggleStyle(.switch)
                                    .onChange(of: toastStyle.showNote) { newValue in updateStyle { $0.showNote = newValue } }
                            }
                        }
                        .settingsCardStyle()
                    }

                    settingsSection(
                        title: NSLocalizedString("toast.behavior", comment: "")
                    ) {
                        VStack(spacing: 0) {
                            SettingsRow(
                                title: NSLocalizedString("toast.enabled", comment: ""),
                                description: NSLocalizedString("toast.enabled.desc", comment: "")
                            ) {
                                Toggle("", isOn: $toastStyle.isEnabled)
                                    .toggleStyle(.switch)
                                    .onChange(of: toastStyle.isEnabled) { newValue in updateStyle { $0.isEnabled = newValue } }
                            }

                            Divider()

                            SettingsRow(
                                title: NSLocalizedString("toast.always.on.top", comment: ""),
                                description: NSLocalizedString("toast.always.on.top.desc", comment: "")
                            ) {
                                Toggle("", isOn: $toastStyle.alwaysOnTop)
                                    .toggleStyle(.switch)
                                    .onChange(of: toastStyle.alwaysOnTop) { newValue in updateStyle { $0.alwaysOnTop = newValue } }
                            }

                            Divider()

                            SettingsRow(
                                title: NSLocalizedString("toast.display.duration", comment: ""),
                                description: NSLocalizedString("toast.display.duration.desc", comment: "")
                            ) {
                                HStack(spacing: 8) {
                                    Slider(value: $toastStyle.displayDuration, in: 0.1...3, step: 0.1)
                                        .frame(width: 140)
                                        .onChange(of: toastStyle.displayDuration) { newValue in updateStyle { $0.displayDuration = newValue } }
                                    Text(String(format: "%.1fs", toastStyle.displayDuration))
                                        .font(.system(size: 12, design: .monospaced))
                                        .frame(width: 42, alignment: .trailing)
                                }
                            }

                            Divider()

                            SettingsRow(
                                title: NSLocalizedString("toast.fade.duration", comment: ""),
                                description: NSLocalizedString("toast.fade.duration.desc", comment: "")
                            ) {
                                HStack(spacing: 8) {
                                    Slider(value: $toastStyle.fadeOutDuration, in: 0.1...3, step: 0.1)
                                        .frame(width: 140)
                                        .onChange(of: toastStyle.fadeOutDuration) { newValue in updateStyle { $0.fadeOutDuration = newValue } }
                                    Text(String(format: "%.1fs", toastStyle.fadeOutDuration))
                                        .font(.system(size: 12, design: .monospaced))
                                        .frame(width: 42, alignment: .trailing)
                                }
                            }
                        }
                        .settingsCardStyle()
                    }

                    settingsSection(
                        title: NSLocalizedString("toast.appearance", comment: "")
                    ) {
                        VStack(spacing: 0) {
                            SettingsRow(
                                title: NSLocalizedString("toast.bg.color", comment: ""),
                                description: NSLocalizedString("toast.bg.color.desc", comment: "")
                            ) {
                                PositionedColorPicker(color: $toastStyle.bgColor)
                                    .frame(width: 32, height: 24)
                                    .onChange(of: toastStyle.bgColor) { newValue in updateStyle { $0.bgColor = newValue } }
                            }

                            Divider()

                            SettingsRow(
                                title: NSLocalizedString("toast.text.color", comment: ""),
                                description: NSLocalizedString("toast.text.color.desc", comment: "")
                            ) {
                                PositionedColorPicker(color: $toastStyle.textColor)
                                    .frame(width: 32, height: 24)
                                    .onChange(of: toastStyle.textColor) { newValue in updateStyle { $0.textColor = newValue } }
                            }

                            Divider()

                            SettingsRow(
                                title: NSLocalizedString("toast.corner.radius", comment: ""),
                                description: NSLocalizedString("toast.corner.radius.desc", comment: "")
                            ) {
                                HStack(spacing: 8) {
                                    Slider(value: $toastStyle.cornerRadius, in: 0...20, step: 1)
                                        .frame(width: 140)
                                        .onChange(of: toastStyle.cornerRadius) { newValue in updateStyle { $0.cornerRadius = newValue } }
                                    Text("\(Int(toastStyle.cornerRadius))")
                                        .font(.system(size: 12, design: .monospaced))
                                        .frame(width: 30, alignment: .trailing)
                                }
                            }

                            Divider()

                            SettingsRow(
                                title: NSLocalizedString("toast.font.size", comment: ""),
                                description: NSLocalizedString("toast.font.size.desc", comment: "")
                            ) {
                                HStack(spacing: 8) {
                                    Slider(value: $toastStyle.fontSize, in: 10...24, step: 1)
                                        .frame(width: 140)
                                        .onChange(of: toastStyle.fontSize) { newValue in updateStyle { $0.fontSize = newValue } }
                                    Text("\(Int(toastStyle.fontSize))")
                                        .font(.system(size: 12, design: .monospaced))
                                        .frame(width: 30, alignment: .trailing)
                                }
                            }
                        }
                        .settingsCardStyle()
                    }

                    Button(action: {
                        ToastManager.shared.style = toastStyle
                        ToastManager.shared.previewToast()
                    }) {
                        Label(NSLocalizedString("toast.preview", comment: ""), systemImage: "text.bubble")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!toastStyle.isEnabled)
                }
                .padding(20)
        }
        .onAppear {
            toastStyle = ToastManager.shared.style
        }
    }

    private func updateStyle(_ mutation: (inout ToastStyle) -> Void) {
        var style = ToastManager.shared.style
        mutation(&style)
        ToastManager.shared.style = style
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.bottom, 12)

            content()
        }
    }
}

// MARK: - SettingsRow
// 通用设置行组件，左侧标题+描述，右侧自定义内容

struct SettingsRow<Content: View>: View {
    // 设置项标题
    let title: String
    // 设置项描述文字
    let description: String
    // 右侧自定义内容（如 Toggle、Picker、Button 等）
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

private extension View {
    func settingsCardStyle() -> some View {
        self
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
    }
}
