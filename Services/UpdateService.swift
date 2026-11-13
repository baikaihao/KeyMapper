import Foundation
import Combine
import AppKit

// 标题和正文可以为 null；旧缓存中也可能没有附件字段。
nonisolated struct GitHubRelease: Codable, Sendable {
    let tagName: String
    let htmlUrl: URL
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case assets
    }

    init(tagName: String, htmlUrl: URL, assets: [GitHubReleaseAsset] = []) {
        self.tagName = tagName
        self.htmlUrl = htmlUrl
        self.assets = assets
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try values.decode(String.self, forKey: .tagName)
        htmlUrl = try values.decode(URL.self, forKey: .htmlUrl)
        assets = try values.decodeIfPresent([GitHubReleaseAsset].self, forKey: .assets) ?? []
    }

    var releasePageURL: URL? {
        guard htmlUrl.scheme == "https", htmlUrl.host == "github.com",
              htmlUrl.path.hasPrefix("/baikaihao/KeyMapper/releases/tag/") else { return nil }
        return htmlUrl
    }

    var installableAsset: GitHubReleaseAsset? {
        assets.first { $0.isInstallable(for: tagName) }
    }
}

nonisolated struct GitHubReleaseAsset: Codable, Sendable {
    let name: String
    let size: Int64
    let downloadURL: URL
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name, size, digest
        case downloadURL = "browser_download_url"
    }

    var sha256: String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        let hash = String(digest.dropFirst(7)).lowercased()
        guard hash.count == 64, hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return hash
    }

    func isInstallable(for tag: String) -> Bool {
        // 沿用现有的通用发布包；缺少校验值或只有源码包时仍提供手动下载。
        ["KeyMapper.app.zip", "KeyMapper.zip"].contains(name) && size > 0 && size <= 256 * 1024 * 1024 &&
        sha256 != nil && downloadURL.scheme == "https" && downloadURL.host == "github.com" &&
        downloadURL.user == nil && downloadURL.password == nil && downloadURL.port == nil &&
        downloadURL.query == nil && downloadURL.fragment == nil &&
        downloadURL.path == "/baikaihao/KeyMapper/releases/download/\(tag)/\(name)"
    }
}

// 支持 v 前缀、缺省补丁号、预发布版本和构建元数据；无效标签不能被误判为最新版。
nonisolated struct UpdateVersion: Comparable, Sendable {
    private let numbers: [Int]
    private let prerelease: [String]

    init?(_ value: String) {
        var version = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.hasPrefix("v") || version.hasPrefix("V") { version.removeFirst() }
        let build = version.split(separator: "+", omittingEmptySubsequences: false)
        guard build.count <= 2 else { return nil }
        if build.count == 2 && !Self.validIdentifiers(String(build[1])) { return nil }
        let parts = build[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(core.count), core.allSatisfy({
            Self.isNumber(String($0)) && ($0.count == 1 || $0.first != "0") && Int($0) != nil
        }) else { return nil }
        let numbers = core.compactMap { Int($0) }
        self.numbers = numbers + Array(repeating: 0, count: 3 - numbers.count)
        if parts.count == 2 {
            let suffix = String(parts[1])
            guard Self.validIdentifiers(suffix) else { return nil }
            let identifiers = suffix.components(separatedBy: ".")
            guard identifiers.allSatisfy({ !Self.isNumber($0) || $0.count == 1 || $0.first != "0" }) else { return nil }
            prerelease = identifiers
        } else {
            prerelease = []
        }
    }

    private static func isNumber(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func validIdentifiers(_ value: String) -> Bool {
        value.components(separatedBy: ".").allSatisfy { identifier in
            !identifier.isEmpty && identifier.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
            }
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.numbers != rhs.numbers { return lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            let leftIsNumber = isNumber(left)
            let rightIsNumber = isNumber(right)
            if leftIsNumber != rightIsNumber { return leftIsNumber }
            if leftIsNumber && left.count != right.count { return left.count < right.count }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    enum CheckResult {
        case available(GitHubRelease)
        case ready(GitHubRelease)
        case upToDate
        case noReleases
        case failed(String)

        var title: String {
            switch self {
            case .available: return NSLocalizedString("update.available.title", comment: "")
            case .ready: return NSLocalizedString("update.ready.title", comment: "")
            case .upToDate: return NSLocalizedString("update.latest.title", comment: "")
            case .noReleases: return NSLocalizedString("update.none.title", comment: "")
            case .failed: return NSLocalizedString("update.error.title", comment: "")
            }
        }

        func message(currentVersion: String) -> String {
            switch self {
            case .available(let release):
                return String(format: NSLocalizedString("update.available.message", comment: ""), release.tagName, currentVersion)
            case .ready(let release):
                return String(format: NSLocalizedString("update.ready.message", comment: ""), release.tagName)
            case .upToDate: return NSLocalizedString("update.latest.message", comment: "")
            case .noReleases: return NSLocalizedString("update.none.message", comment: "")
            case .failed(let message): return message
            }
        }
    }

    enum InstallationState {
        case idle
        case downloading
        case ready(PreparedUpdate)
        case installing
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .downloading, .installing: return true
            default: return false
            }
        }
    }

    @Published private(set) var isChecking = false
    @Published private(set) var automaticallyChecksForUpdates: Bool
    @Published private(set) var automaticallyDownloadsUpdates: Bool
    @Published private(set) var installationState: InstallationState = .idle
    @Published private(set) var availableRelease: GitHubRelease?
    @Published private(set) var lastCheckDate: Date?
    // 由主窗口统一展示，切换页面或从菜单触发都不会丢失检查结果。
    @Published var result: CheckResult?

    let currentVersion: String
    let buildNumber: String
    private let session: URLSession
    private let defaults: UserDefaults
    private let now: () -> Date
    private let installer: UpdateInstaller
    private let prepareUpdate: @Sendable (GitHubRelease) async throws -> PreparedUpdate
    private var downloadTask: Task<Void, Never>?
    private var downloadIsAutomatic = false
    private var automaticCheckTask: Task<Void, Never>?
    private var automaticChecksStarted = false
    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60
    private static let automaticChecksKey = "setting_automatically_check_updates"
    private static let automaticDownloadsKey = "setting_automatically_download_updates"
    private static let pendingInstallationKey = "update_pending_installation"
    private static let lastCheckKey = "update_last_check_date"
    private static let cachedReleaseKey = "update_cached_release"
    private static let notifiedVersionKey = "update_last_notified_version"
    private let releasesURL = URL(string: "https://github.com/baikaihao/KeyMapper/releases")!
    private let latestReleaseURL = URL(string: "https://api.github.com/repos/baikaihao/KeyMapper/releases/latest")!

    init(session: URLSession = .shared, currentVersion: String? = nil, bundle: Bundle = .main,
         defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         prepareUpdate: (@Sendable (GitHubRelease) async throws -> PreparedUpdate)? = nil) {
        self.session = session
        self.defaults = defaults
        self.now = now
        self.currentVersion = currentVersion ?? bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let installer = UpdateInstaller(session: session, installedAppURL: bundle.bundleURL,
                                        currentVersion: self.currentVersion)
        self.installer = installer
        self.prepareUpdate = prepareUpdate ?? { try await installer.prepare($0) }
        buildNumber = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        automaticallyChecksForUpdates = defaults.object(forKey: Self.automaticChecksKey) as? Bool ?? true
        automaticallyDownloadsUpdates = defaults.object(forKey: Self.automaticDownloadsKey) as? Bool ?? true
        lastCheckDate = defaults.object(forKey: Self.lastCheckKey) as? Date
        if let data = defaults.data(forKey: Self.cachedReleaseKey),
           let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
           let remote = UpdateVersion(release.tagName), let current = UpdateVersion(self.currentVersion),
           remote > current, release.releasePageURL != nil {
            availableRelease = release
        }
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        automaticallyChecksForUpdates = enabled
        defaults.set(enabled, forKey: Self.automaticChecksKey)
        if !enabled { cancelAutomaticDownload() }
        if enabled, automaticallyDownloadsUpdates, let release = availableRelease {
            downloadUpdate(release, automatically: true)
        }
        scheduleAutomaticCheck()
    }

    func setAutomaticDownloadsEnabled(_ enabled: Bool) {
        automaticallyDownloadsUpdates = enabled
        defaults.set(enabled, forKey: Self.automaticDownloadsKey)
        if enabled, automaticallyChecksForUpdates, let release = availableRelease {
            downloadUpdate(release, automatically: true)
        } else if !enabled {
            cancelAutomaticDownload()
        }
    }

    func startAutomaticChecks() {
        guard !automaticChecksStarted else { return }
        automaticChecksStarted = true
        recoverPreviousInstallation()
        if automaticallyChecksForUpdates, automaticallyDownloadsUpdates,
           case .idle = installationState, let release = availableRelease {
            downloadUpdate(release, automatically: true)
        }
        scheduleAutomaticCheck()
    }

    func stopAutomaticChecks() {
        automaticChecksStarted = false
        automaticCheckTask?.cancel()
        automaticCheckTask = nil
        downloadTask?.cancel()
        downloadTask = nil
        if case .downloading = installationState { installationState = .idle }
        if case .ready = installationState {
            discardPreparedUpdate()
            installationState = .idle
        }
    }

    private var timeUntilAutomaticCheck: TimeInterval {
        guard let lastCheckDate else { return 0 }
        let elapsed = now().timeIntervalSince(lastCheckDate)
        // 系统时间回拨后重新检查，避免未来时间戳无限期推迟更新检查。
        return elapsed < 0 ? 0 : max(0, Self.automaticCheckInterval - elapsed)
    }

    private func scheduleAutomaticCheck() {
        automaticCheckTask?.cancel()
        automaticCheckTask = nil
        guard automaticChecksStarted, automaticallyChecksForUpdates else { return }
        // 避开启动阶段；持续运行时也会继续检查，重启后仍遵守持久化的每日间隔。
        let delay = max(10, timeUntilAutomaticCheck)
        automaticCheckTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            await self.checkForUpdates(automatically: true)
            guard !Task.isCancelled else { return }
            self.scheduleAutomaticCheck()
        }
    }

    // 仅由 AppDelegate 在主窗口可见且应用激活时调用，后台检查不抢焦点。
    func presentAutomaticUpdateIfNeeded() {
        guard automaticallyChecksForUpdates, result == nil, let release = availableRelease,
              !installationState.isBusy,
              defaults.string(forKey: Self.notifiedVersionKey) != release.tagName else { return }
        defaults.set(release.tagName, forKey: Self.notifiedVersionKey)
        if case .ready = installationState {
            result = .ready(release)
        } else {
            result = .available(release)
        }
    }

    func checkForUpdates(automatically: Bool = false) async {
        if automatically {
            guard automaticallyChecksForUpdates, timeUntilAutomaticCheck == 0 else { return }
        }
        guard !isChecking else { return }
        if case .installing = installationState { return }
        isChecking = true
        if !automatically { result = nil }
        // 记录尝试时间；断网或限流时不在后台反复请求，手动检查仍随时可用。
        lastCheckDate = now()
        defaults.set(lastCheckDate, forKey: Self.lastCheckKey)
        defer { isChecking = false }

        var request = URLRequest(url: latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("KeyMapper/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
            switch response.statusCode {
            case 200: break
            case 404:
                saveAvailableRelease(nil)
                if !automatically { result = .noReleases }
                return
            case 403, 429: throw UpdateError.rateLimited
            default: throw UpdateError.httpStatus(response.statusCode)
            }

            let release: GitHubRelease
            do {
                release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            } catch {
                throw UpdateError.invalidResponse
            }
            guard let remote = UpdateVersion(release.tagName),
                  let current = UpdateVersion(currentVersion) else { throw UpdateError.invalidVersion }
            guard release.releasePageURL != nil else { throw UpdateError.invalidResponse }
            saveAvailableRelease(remote > current ? release : nil)
            if remote > current, automaticallyDownloadsUpdates {
                downloadUpdate(release, automatically: automatically)
            }
            if !automatically {
                if remote > current {
                    defaults.set(release.tagName, forKey: Self.notifiedVersionKey)
                    if case .ready = installationState {
                        result = .ready(release)
                    } else if !installationState.isBusy {
                        result = .available(release)
                    }
                } else {
                    result = .upToDate
                }
            }
        } catch {
            // URLSession 取消时可能抛出 URLError.cancelled，而不是 CancellationError。
            if !automatically && !Task.isCancelled && !(error is CancellationError) {
                result = .failed(error.localizedDescription)
            }
        }
    }

    private func saveAvailableRelease(_ release: GitHubRelease?) {
        if availableRelease?.tagName != release?.tagName {
            downloadTask?.cancel()
            downloadTask = nil
            discardPreparedUpdate()
            installationState = .idle
        }
        availableRelease = release
        if let release, let data = try? JSONEncoder().encode(release) {
            defaults.set(data, forKey: Self.cachedReleaseKey)
        } else {
            defaults.removeObject(forKey: Self.cachedReleaseKey)
        }
    }

    var updateActionTitle: String {
        switch installationState {
        case .downloading: return NSLocalizedString("update.downloading", comment: "")
        case .ready: return NSLocalizedString("update.restart", comment: "")
        case .installing: return NSLocalizedString("update.installing", comment: "")
        default: return NSLocalizedString("update.download", comment: "")
        }
    }

    func performUpdateAction() {
        guard let release = availableRelease, !installationState.isBusy else { return }
        if case .ready = installationState {
            Task { await restartAndInstall() }
        } else if release.installableAsset != nil {
            downloadUpdate(release)
        } else {
            openReleasePage(for: release)
        }
    }

    func downloadUpdate(_ release: GitHubRelease, automatically: Bool = false) {
        if automatically, !automaticallyChecksForUpdates || !automaticallyDownloadsUpdates { return }
        guard release.installableAsset != nil, !installationState.isBusy else { return }
        if case .ready(let prepared) = installationState, prepared.release.tagName == release.tagName { return }
        discardPreparedUpdate()
        downloadIsAutomatic = automatically
        installationState = .downloading
        downloadTask = Task { [weak self, prepareUpdate] in
            do {
                let update = try await prepareUpdate(release)
                guard let self, !Task.isCancelled else {
                    await Self.removeUpdateDirectory(update.directory)
                    return
                }
                self.installationState = .ready(update)
                if !automatically { self.result = .ready(release) }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.installationState = .failed(error.localizedDescription)
            }
        }
    }

    private func cancelAutomaticDownload() {
        guard downloadIsAutomatic, case .downloading = installationState else { return }
        downloadTask?.cancel()
        downloadTask = nil
        installationState = .idle
    }

    private func discardPreparedUpdate() {
        if case .ready(let update) = installationState {
            Task { await Self.removeUpdateDirectory(update.directory) }
        }
    }

    @concurrent private static func removeUpdateDirectory(_ url: URL) async {
        try? FileManager.default.removeItem(at: url)
    }

    func restartAndInstall() async {
        guard case .ready(let update) = installationState else { return }
        installationState = .installing
        do {
            let plan = try await installer.stage(update)
            do {
                let process = try plan.process()
                defaults.set(try JSONEncoder().encode(plan), forKey: Self.pendingInstallationKey)
                // 先保证交接信息持久化，再退出；新版本启动后才清理原版本备份。
                defaults.synchronize()
                try process.run()
            } catch {
                defaults.removeObject(forKey: Self.pendingInstallationKey)
                await Self.removeUpdateDirectory(plan.workspace)
                throw error
            }
            NSApp.terminate(nil)
        } catch {
            // 启动安装助手失败时应用保持运行，用户仍可手动下载。
            await Self.removeUpdateDirectory(update.directory)
            installationState = .failed(error.localizedDescription)
            result = .failed(error.localizedDescription)
        }
    }

    private func recoverPreviousInstallation() {
        guard let data = defaults.data(forKey: Self.pendingInstallationKey),
              let plan = try? JSONDecoder().decode(UpdateInstallPlan.self, from: data) else { return }
        // 只处理本应用在相邻目录创建的安装工作区，不能按偏好设置中的任意路径删除文件。
        let destination = installer.installedAppURL.resolvingSymlinksInPath()
        guard plan.destination == destination,
              plan.workspace.resolvingSymlinksInPath() == plan.workspace,
              plan.workspace.deletingLastPathComponent() == destination.deletingLastPathComponent(),
              plan.workspace.lastPathComponent.hasPrefix(".KeyMapper-update-"),
              UUID(uuidString: String(plan.workspace.lastPathComponent.dropFirst(".KeyMapper-update-".count))) != nil,
              let status = try? String(contentsOf: plan.statusURL, encoding: .utf8) else { return }
        defaults.removeObject(forKey: Self.pendingInstallationKey)
        if status != "success" {
            installationState = .failed(UpdateInstallationError.installationFailed.localizedDescription)
        }
        // 若回滚失败，必须保留 Previous.app，供用户恢复。
        if status == "success" || !FileManager.default.fileExists(atPath: plan.backupApp.path) {
            Task { await Self.removeUpdateDirectory(plan.workspace) }
        }
        if plan.downloadDirectory.deletingLastPathComponent().resolvingSymlinksInPath() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath(),
           plan.downloadDirectory.lastPathComponent.hasPrefix("KeyMapperUpdate-"),
           UUID(uuidString: String(plan.downloadDirectory.lastPathComponent.dropFirst("KeyMapperUpdate-".count))) != nil {
            Task { await Self.removeUpdateDirectory(plan.downloadDirectory) }
        }
    }

    func openReleasePage(for release: GitHubRelease? = nil) {
        NSWorkspace.shared.open(release?.releasePageURL ?? releasesURL)
    }
}

enum UpdateError: LocalizedError {
    case invalidResponse
    case invalidVersion
    case rateLimited
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return NSLocalizedString("update.error.invalid.response", comment: "")
        case .invalidVersion: return NSLocalizedString("update.error.invalid.version", comment: "")
        case .rateLimited: return NSLocalizedString("update.error.rate.limited", comment: "")
        case .httpStatus(let status):
            return String(format: NSLocalizedString("update.error.http", comment: ""), status)
        }
    }
}
