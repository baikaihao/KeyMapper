import Foundation
import Combine
import AppKit

// 只解码检查更新需要的字段，避免可空的 Release 标题/正文导致整个检查失败。
struct GitHubRelease: Codable, Sendable {
    let tagName: String
    let htmlUrl: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
    }

    var releasePageURL: URL? {
        guard htmlUrl.scheme == "https", htmlUrl.host == "github.com",
              htmlUrl.path.hasPrefix("/baikaihao/KeyMapper/releases/tag/") else { return nil }
        return htmlUrl
    }
}

// 支持 v 前缀、缺省补丁号、预发布版本和构建元数据；无效标签不能被误判为最新版。
struct UpdateVersion: Comparable {
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
        case upToDate
        case noReleases
        case failed(String)

        var title: String {
            switch self {
            case .available: return NSLocalizedString("update.available.title", comment: "")
            case .upToDate: return NSLocalizedString("update.latest.title", comment: "")
            case .noReleases: return NSLocalizedString("update.none.title", comment: "")
            case .failed: return NSLocalizedString("update.error.title", comment: "")
            }
        }

        func message(currentVersion: String) -> String {
            switch self {
            case .available(let release):
                return String(format: NSLocalizedString("update.available.message", comment: ""), release.tagName, currentVersion)
            case .upToDate: return NSLocalizedString("update.latest.message", comment: "")
            case .noReleases: return NSLocalizedString("update.none.message", comment: "")
            case .failed(let message): return message
            }
        }
    }

    @Published private(set) var isChecking = false
    @Published private(set) var automaticallyChecksForUpdates: Bool
    @Published private(set) var availableRelease: GitHubRelease?
    @Published private(set) var lastCheckDate: Date?
    // 由主窗口统一展示，切换页面或从菜单触发都不会丢失检查结果。
    @Published var result: CheckResult?

    let currentVersion: String
    let buildNumber: String
    private let session: URLSession
    private let defaults: UserDefaults
    private let now: () -> Date
    private var automaticCheckTask: Task<Void, Never>?
    private var automaticChecksStarted = false
    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60
    private static let automaticChecksKey = "setting_automatically_check_updates"
    private static let lastCheckKey = "update_last_check_date"
    private static let cachedReleaseKey = "update_cached_release"
    private static let notifiedVersionKey = "update_last_notified_version"
    private let releasesURL = URL(string: "https://github.com/baikaihao/KeyMapper/releases")!
    private let latestReleaseURL = URL(string: "https://api.github.com/repos/baikaihao/KeyMapper/releases/latest")!

    init(session: URLSession = .shared, currentVersion: String? = nil, bundle: Bundle = .main,
         defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.defaults = defaults
        self.now = now
        self.currentVersion = currentVersion ?? bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        buildNumber = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        automaticallyChecksForUpdates = defaults.object(forKey: Self.automaticChecksKey) as? Bool ?? true
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
        scheduleAutomaticCheck()
    }

    func startAutomaticChecks() {
        guard !automaticChecksStarted else { return }
        automaticChecksStarted = true
        scheduleAutomaticCheck()
    }

    func stopAutomaticChecks() {
        automaticChecksStarted = false
        automaticCheckTask?.cancel()
        automaticCheckTask = nil
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
              defaults.string(forKey: Self.notifiedVersionKey) != release.tagName else { return }
        defaults.set(release.tagName, forKey: Self.notifiedVersionKey)
        result = .available(release)
    }

    func checkForUpdates(automatically: Bool = false) async {
        if automatically {
            guard automaticallyChecksForUpdates, timeUntilAutomaticCheck == 0 else { return }
        }
        guard !isChecking else { return }
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
            if !automatically {
                if remote > current {
                    defaults.set(release.tagName, forKey: Self.notifiedVersionKey)
                    result = .available(release)
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
        availableRelease = release
        if let release, let data = try? JSONEncoder().encode(release) {
            defaults.set(data, forKey: Self.cachedReleaseKey)
        } else {
            defaults.removeObject(forKey: Self.cachedReleaseKey)
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
