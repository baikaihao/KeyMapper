import Foundation
import Combine
import AppKit

// MARK: - BackupManager
// 备份管理服务（单例）。
// 负责映射规则的自动/手动备份，以及备份文件的清理管理。
//
// 功能：
// 1. 自动定时备份（可配置间隔天数 1-14 天）
// 2. 备份文件数量上限管理（超出时自动删除最旧的备份）
// 3. 自定义备份路径（默认 ~/Documents/KeyMapperRules）
// 4. 备份内容包含映射规则、黑名单、暂停热键
// 5. 提供文件夹选择器（NSOpenPanel）

class BackupManager: ObservableObject {
    static let shared = BackupManager()

    // MARK: - 发布属性（UI 绑定 + 自动持久化）

    // 是否启用自动备份
    @Published var autoBackupEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(autoBackupEnabled, forKey: "setting_auto_backup_enabled")
            if autoBackupEnabled {
                scheduleNextBackup()
            } else {
                cancelScheduledBackup()
            }
        }
    }

    // 自动备份间隔天数（1-14）
    @Published var backupIntervalDays: Int = 7 {
        didSet {
            UserDefaults.standard.set(backupIntervalDays, forKey: "setting_backup_interval_days")
            if autoBackupEnabled {
                scheduleNextBackup()
            }
        }
    }

    // 备份文件最大保留数量，超出时自动清理最旧的备份
    @Published var maxBackupCount: Int = 5 {
        didSet {
            UserDefaults.standard.set(maxBackupCount, forKey: "setting_max_backup_count")
        }
    }

    // 备份文件存储路径
    @Published var backupPath: String = "" {
        didSet {
            UserDefaults.standard.set(backupPath, forKey: "setting_backup_path")
        }
    }

    // 上次备份时间
    @Published var lastBackupDate: Date? = nil {
        didSet {
            UserDefaults.standard.set(lastBackupDate, forKey: "setting_last_backup_date")
        }
    }

    // 自动备份定时器
    private var backupTimer: Timer?

    // 默认备份路径：~/Documents/KeyMapperRules
    private var defaultBackupPath: String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let keymapperPath = documentsPath.appendingPathComponent("KeyMapperRules")
        return keymapperPath.path
    }

    // MARK: - 初始化

    init() {
        let savedAutoBackup = UserDefaults.standard.bool(forKey: "setting_auto_backup_enabled")
        let savedInterval = UserDefaults.standard.integer(forKey: "setting_backup_interval_days")
        let savedMaxCount = UserDefaults.standard.integer(forKey: "setting_max_backup_count")
        let savedPath = UserDefaults.standard.string(forKey: "setting_backup_path")
        let savedLastDate = UserDefaults.standard.object(forKey: "setting_last_backup_date") as? Date

        self.autoBackupEnabled = savedAutoBackup
        self.backupIntervalDays = savedInterval > 0 ? savedInterval : 7
        self.maxBackupCount = savedMaxCount > 0 ? savedMaxCount : 5
        self.backupPath = (savedPath?.isEmpty ?? true) ? defaultBackupPath : savedPath!
        self.lastBackupDate = savedLastDate

        ensureBackupDirectoryExists()

        if autoBackupEnabled {
            checkAndScheduleBackup()
        }
    }

    // 确保备份目录存在，不存在则创建
    private func ensureBackupDirectoryExists() {
        let backupDir = URL(fileURLWithPath: backupPath)
        do {
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create backup directory: \(error.localizedDescription)")
        }
    }

    // 检查是否需要立即备份（距上次备份已超过间隔天数），然后调度下一次备份
    private func checkAndScheduleBackup() {
        if let lastDate = lastBackupDate {
            let calendar = Calendar.current
            let daysSinceLastBackup = calendar.dateComponents([.day], from: lastDate, to: Date()).day ?? 0

            if daysSinceLastBackup >= backupIntervalDays {
                performBackup()
            }
        }
        scheduleNextBackup()
    }

    // 调度下一次自动备份定时器
    private func scheduleNextBackup() {
        cancelScheduledBackup()

        let interval: TimeInterval = TimeInterval(backupIntervalDays * 24 * 60 * 60)

        backupTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.performBackup()
            // 备份完成后重新调度下一次
            self?.scheduleNextBackup()
        }
    }

    // 取消已调度的自动备份定时器
    private func cancelScheduledBackup() {
        backupTimer?.invalidate()
        backupTimer = nil
    }

    // MARK: - 备份执行

    // 执行一次备份操作。
    // 将当前映射规则、黑名单、暂停热键导出为 JSON 文件，
    // 文件名格式：keymapper_backup_{yyyyMMdd_HHmmss}.json
    func performBackup() {
        let engine = MyEngine.shared

        // 构建备份配置字典，版本号用于未来兼容性检查
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

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let fileName = "keymapper_backup_\(timestamp).json"

        let backupDir = URL(fileURLWithPath: backupPath)
        let backupURL = backupDir.appendingPathComponent(fileName)

        do {
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true, attributes: nil)
            let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
            try data.write(to: backupURL)
            lastBackupDate = Date()
            print("Backup saved to: \(backupURL.path)")

            cleanupOldBackups()
        } catch {
            print("Backup failed: \(error.localizedDescription)")
        }
    }

    // 清理超出数量上限的旧备份文件，按修改时间从旧到新删除
    private func cleanupOldBackups() {
        let backupDir = URL(fileURLWithPath: backupPath)

        do {
            let files = try FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)

            // 筛选备份文件并按修改时间降序排列（最新在前）
            let backupFiles = files
                .filter { $0.lastPathComponent.hasPrefix("keymapper_backup_") && $0.pathExtension == "json" }
                .sorted {
                    let date1 = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    let date2 = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    return (date1 ?? Date.distantPast) > (date2 ?? Date.distantPast)
                }

            // 删除超出上限的旧备份
            if backupFiles.count > maxBackupCount {
                let filesToDelete = backupFiles.dropFirst(maxBackupCount)
                for file in filesToDelete {
                    try? FileManager.default.removeItem(at: file)
                    print("Deleted old backup: \(file.lastPathComponent)")
                }
            }
        } catch {
            print("Failed to cleanup old backups: \(error.localizedDescription)")
        }
    }

    // MARK: - 文件夹选择

    // 弹出文件夹选择面板，让用户选择备份存储路径
    func selectBackupFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = NSLocalizedString("settings.backup.select.folder", comment: "")
        panel.directoryURL = URL(fileURLWithPath: backupPath)

        if panel.runModal() == .OK, let url = panel.url {
            return url.path
        }
        return nil
    }

    // 在 Finder 中打开备份文件夹
    func openBackupFolder() {
        let backupDir = URL(fileURLWithPath: backupPath)
        NSWorkspace.shared.open(backupDir)
    }
}
