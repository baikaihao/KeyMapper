import Foundation
import Combine
import AppKit

class BackupManager: ObservableObject {
    static let shared = BackupManager()
    
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
    
    @Published var backupIntervalDays: Int = 7 {
        didSet {
            UserDefaults.standard.set(backupIntervalDays, forKey: "setting_backup_interval_days")
            if autoBackupEnabled {
                scheduleNextBackup()
            }
        }
    }
    
    @Published var maxBackupCount: Int = 5 {
        didSet {
            UserDefaults.standard.set(maxBackupCount, forKey: "setting_max_backup_count")
        }
    }
    
    @Published var backupPath: String = "" {
        didSet {
            UserDefaults.standard.set(backupPath, forKey: "setting_backup_path")
        }
    }
    
    @Published var lastBackupDate: Date? = nil {
        didSet {
            UserDefaults.standard.set(lastBackupDate, forKey: "setting_last_backup_date")
        }
    }
    
    private var backupTimer: Timer?
    
    private var defaultBackupPath: String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let keymapperPath = documentsPath.appendingPathComponent("KeyMapperRules")
        return keymapperPath.path
    }
    
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
    
    private func ensureBackupDirectoryExists() {
        let backupDir = URL(fileURLWithPath: backupPath)
        do {
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create backup directory: \(error.localizedDescription)")
        }
    }
    
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
    
    private func scheduleNextBackup() {
        cancelScheduledBackup()
        
        let interval: TimeInterval = TimeInterval(backupIntervalDays * 24 * 60 * 60)
        
        backupTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.performBackup()
            self?.scheduleNextBackup()
        }
    }
    
    private func cancelScheduledBackup() {
        backupTimer?.invalidate()
        backupTimer = nil
    }
    
    func performBackup() {
        let engine = MyEngine.shared
        
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
    
    private func cleanupOldBackups() {
        let backupDir = URL(fileURLWithPath: backupPath)
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
            
            let backupFiles = files
                .filter { $0.lastPathComponent.hasPrefix("keymapper_backup_") && $0.pathExtension == "json" }
                .sorted { 
                    let date1 = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    let date2 = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    return (date1 ?? Date.distantPast) > (date2 ?? Date.distantPast)
                }
            
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
    
    func openBackupFolder() {
        let backupDir = URL(fileURLWithPath: backupPath)
        NSWorkspace.shared.open(backupDir)
    }
}
