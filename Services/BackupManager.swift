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
            guard autoBackupEnabled != oldValue else { return }
            if autoBackupEnabled {
                scheduleNextBackup(resetDeadline: true)
            } else {
                cancelScheduledBackup()
                nextBackupDate = nil
            }
        }
    }

    // 自动备份间隔天数（1-14）
    @Published var backupIntervalDays: Int = 7 {
        didSet {
            UserDefaults.standard.set(backupIntervalDays, forKey: "setting_backup_interval_days")
            if autoBackupEnabled && backupIntervalDays != oldValue {
                scheduleNextBackup(resetDeadline: true)
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

    // 当前是否仍有备份请求正在执行或等待串行队列处理。
    @Published private(set) var isBackupInProgress = false

    // 最近一次备份错误会保留到下次成功，避免自动备份失败后用户毫无感知。
    @Published private(set) var lastBackupError: String? = nil {
        didSet {
            if let lastBackupError {
                UserDefaults.standard.set(lastBackupError, forKey: Self.lastBackupErrorKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastBackupErrorKey)
            }
        }
    }

    // 当前自动备份截止时间；持久化后可跨重启继续原来的调度。
    @Published private(set) var nextBackupDate: Date? = nil {
        didSet {
            if let nextBackupDate {
                UserDefaults.standard.set(nextBackupDate, forKey: Self.nextBackupDateKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.nextBackupDateKey)
            }
        }
    }

    // 自动备份定时器
    private var backupTimer: Timer?
    private var pendingBackupCount = 0
    // 编码、磁盘写入和清理必须离开 Event Tap 所在的主 RunLoop。
    private let backupQueue = DispatchQueue(label: "com.keymapper.backup", qos: .utility)

    // 自动备份失败后短暂等待再重试，避免到期状态下形成立即重试循环。
    private static let failedBackupRetryInterval: TimeInterval = 60 * 60
    private static let nextBackupDateKey = "setting_next_backup_date"
    private static let lastBackupErrorKey = "setting_last_backup_error"

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
        self.backupIntervalDays = savedInterval == 0 ? 7 : min(max(savedInterval, 1), 14)
        self.maxBackupCount = savedMaxCount == 0 ? 5 : min(max(savedMaxCount, 1), 20)
        self.backupPath = (savedPath?.isEmpty ?? true) ? defaultBackupPath : savedPath!
        self.lastBackupDate = savedLastDate
        self.lastBackupError = UserDefaults.standard.string(forKey: Self.lastBackupErrorKey)
        self.nextBackupDate = UserDefaults.standard.object(forKey: Self.nextBackupDateKey) as? Date

        UserDefaults.standard.set(backupIntervalDays, forKey: "setting_backup_interval_days")
        UserDefaults.standard.set(maxBackupCount, forKey: "setting_max_backup_count")

        ensureBackupDirectoryExists()

        if autoBackupEnabled {
            checkAndScheduleBackup()
        } else {
            nextBackupDate = nil
            UserDefaults.standard.removeObject(forKey: Self.nextBackupDateKey)
        }
    }

    // 确保备份目录存在，不存在则在后台创建。
    private func ensureBackupDirectoryExists() {
        let backupDir = URL(fileURLWithPath: backupPath)
        backupQueue.async {
            do {
                try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create backup directory: \(error.localizedDescription)")
            }
        }
    }

    // 根据上次成功备份时间恢复调度；已到期时会在当前 RunLoop 周期尽快执行。
    private func checkAndScheduleBackup() {
        scheduleNextBackup()
    }

    // 下一次执行时间锚定在“上次成功时间 + 间隔”，避免每次启动都重置完整周期。
    private func scheduleNextBackup(retryAfterFailure: Bool = false, resetDeadline: Bool = false) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.scheduleNextBackup(
                    retryAfterFailure: retryAfterFailure,
                    resetDeadline: resetDeadline
                )
            }
            return
        }

        cancelScheduledBackup()
        guard autoBackupEnabled else { return }

        let interval = TimeInterval(max(1, backupIntervalDays)) * 24 * 60 * 60
        let now = Date()
        let scheduledDate: Date
        if retryAfterFailure {
            scheduledDate = now.addingTimeInterval(min(Self.failedBackupRetryInterval, interval))
        } else if !resetDeadline, let nextBackupDate {
            scheduledDate = nextBackupDate
        } else if let lastBackupDate {
            scheduledDate = lastBackupDate.addingTimeInterval(interval)
        } else {
            scheduledDate = now.addingTimeInterval(interval)
        }
        let boundedScheduledDate = min(scheduledDate, now.addingTimeInterval(interval))
        nextBackupDate = boundedScheduledDate
        let delay = max(boundedScheduledDate.timeIntervalSince(now), 0.1)

        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.backupTimer = nil
            self?.performAutomaticBackup()
        }
        backupTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    // 取消已调度的自动备份定时器
    private func cancelScheduledBackup() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.cancelScheduledBackup()
            }
            return
        }

        backupTimer?.invalidate()
        backupTimer = nil
    }

    // MARK: - 备份执行

    // 执行一次备份操作。
    // 将当前映射规则、黑名单、暂停热键导出为 JSON 文件，
    // 文件名包含毫秒时间戳和随机后缀，连续备份不会互相覆盖。
    func performBackup() {
        enqueueBackup(isAutomatic: false)
    }

    // 供覆盖配置等需要确认备份结果的流程使用。完成回调始终在主线程执行。
    func performBackupAndReportSuccess(completion: @escaping (Bool) -> Void) {
        enqueueBackup(isAutomatic: false, completion: completion)
    }

    private struct BackupRequest {
        let configuration: MappingStore.Configuration
        let directory: URL
        let maximumBackupCount: Int
    }

    private struct BackupSuccess {
        let date: Date
        let url: URL
    }

    private func performAutomaticBackup() {
        enqueueBackup(isAutomatic: true)
    }

    private func enqueueBackup(
        isAutomatic: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    completion?(false)
                    return
                }
                self.enqueueBackup(isAutomatic: isAutomatic, completion: completion)
            }
            return
        }

        let request = makeBackupRequest()
        pendingBackupCount += 1
        isBackupInProgress = true
        backupQueue.async {
            do {
                let success = try Self.writeBackup(request)
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        completion?(false)
                        return
                    }
                    self.handleBackupSuccess(success)
                    self.finishBackupRequest()
                    completion?(true)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        completion?(false)
                        return
                    }
                    self.handleBackupFailure(error, isAutomatic: isAutomatic)
                    self.finishBackupRequest()
                    completion?(false)
                }
            }
        }
    }

    private func makeBackupRequest() -> BackupRequest {
        let engine = MyEngine.shared
        return BackupRequest(
            configuration: MappingStore.makeConfiguration(
                mappings: engine.list,
                blacklist: engine.blacklist,
                pauseHotkey: engine.pauseHotkey
            ),
            directory: URL(fileURLWithPath: backupPath),
            maximumBackupCount: maxBackupCount
        )
    }

    private func handleBackupSuccess(_ success: BackupSuccess) {
        lastBackupDate = success.date
        lastBackupError = nil
        print("Backup saved to: \(success.url.path)")

        // 手动备份成功也应从新的成功时间重新计算下一次自动备份。
        if autoBackupEnabled {
            scheduleNextBackup(resetDeadline: true)
        }
    }

    private func handleBackupFailure(_ error: Error, isAutomatic: Bool) {
        lastBackupError = error.localizedDescription
        print("Backup failed: \(error.localizedDescription)")
        if isAutomatic && autoBackupEnabled {
            scheduleNextBackup(retryAfterFailure: true)
        }
    }

    private func finishBackupRequest() {
        pendingBackupCount = max(0, pendingBackupCount - 1)
        isBackupInProgress = pendingBackupCount > 0
    }

    private static func writeBackup(_ request: BackupRequest) throws -> BackupSuccess {
        let data = try MappingStore.encodeValidatedConfiguration(request.configuration)

        try FileManager.default.createDirectory(
            at: request.directory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let backupDate = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let timestamp = dateFormatter.string(from: backupDate)
        let uniqueSuffix = UUID().uuidString.prefix(8)
        let fileName = "keymapper_backup_\(timestamp)_\(uniqueSuffix).json"
        let backupURL = request.directory.appendingPathComponent(fileName)
        try data.write(to: backupURL, options: [.atomic, .withoutOverwriting])

        do {
            try cleanupOldBackups(
                in: request.directory,
                maximumBackupCount: request.maximumBackupCount
            )
        } catch {
            print("Failed to cleanup old backups: \(error.localizedDescription)")
        }

        return BackupSuccess(date: backupDate, url: backupURL)
    }

    // 清理超出数量上限的旧备份文件，按修改时间从旧到新删除
    private static func cleanupOldBackups(in backupDir: URL, maximumBackupCount: Int) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )

        // 筛选备份文件并按修改时间降序排列（最新在前）
        let backupFiles = files
            .filter { $0.lastPathComponent.hasPrefix("keymapper_backup_") && $0.pathExtension == "json" }
            .sorted {
                let date1 = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let date2 = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return (date1 ?? Date.distantPast) > (date2 ?? Date.distantPast)
            }

        let retainedCount = max(1, maximumBackupCount)
        if backupFiles.count > retainedCount {
            for file in backupFiles.dropFirst(retainedCount) {
                do {
                    try FileManager.default.removeItem(at: file)
                    print("Deleted old backup: \(file.lastPathComponent)")
                } catch {
                    print("Failed to delete old backup \(file.lastPathComponent): \(error.localizedDescription)")
                }
            }
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
