import Foundation
import Testing
@testable import KeyMapperCore

// 每个 URLSession 自带响应配置，测试之间不共享可变的网络桩状态。
private final class UpdateURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        #expect(request.url?.absoluteString == "https://api.github.com/repos/baikaihao/KeyMapper/releases/latest")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "KeyMapper/2.3.5")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        if request.value(forHTTPHeaderField: "X-Test-Hold") == "true" { return }
        if request.value(forHTTPHeaderField: "X-Test-Offline") == "true" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let status = Int(request.value(forHTTPHeaderField: "X-Test-Status") ?? "200") ?? 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        let data = Data(base64Encoded: request.value(forHTTPHeaderField: "X-Test-Body") ?? "") ?? Data()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class UpdateTestPreferences {
    let name = "KeyMapper.UpdateTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() { defaults = UserDefaults(suiteName: name)! }
    deinit { UserDefaults.standard.removePersistentDomain(forName: name) }
}

@Suite @MainActor
struct UpdateServiceTests {
    private let preferences = UpdateTestPreferences()

    @Test(arguments: [
        ("v2.3.6", "2.3.5", true),
        ("2.10.0", "2.9.9", true),
        ("2.3.5", "2.3.5", false),
        ("2.3.4", "2.3.5", false),
        ("2.3", "2.3.0", false),
        ("2.3.5+20261101", "2.3.5+20261031", false),
        ("2.3.5", "2.3.5-rc.1", true),
        ("2.3.5-rc.1", "2.3.5", false),
        ("2.3.5-beta.10", "2.3.5-beta.2", true),
        ("2.3.5-rc.1", "2.3.5-beta.10", true)
    ])
    func versionsCompareNumerically(remote: String, current: String, newer: Bool) throws {
        let remote = try #require(UpdateVersion(remote))
        let current = try #require(UpdateVersion(current))
        #expect((remote > current) == newer)
    }

    @Test(arguments: ["", "v", "latest", "2.bad.6", "2..6", "2.3.6.1", "2.03.6", "2.3.6-", "2.3.6+", "2.3.6-01", "2.3.6+a+b"])
    func malformedTagsAreRejected(tag: String) {
        #expect(UpdateVersion(tag) == nil)
    }

    private func release(_ tag: String, page: String = "https://github.com/baikaihao/KeyMapper/releases/tag/test") -> String {
        // name/body 为 null 是 GitHub 的合法响应，不能影响版本检查。
        """
        {"tag_name":"\(tag)","html_url":"\(page)","name":null,"body":null,"assets":[]}
        """
    }

    private func service(body: String = "", status: Int = 200, offline: Bool = false, hold: Bool = false,
                         now: @escaping () -> Date = Date.init) -> UpdateService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        configuration.httpAdditionalHeaders = [
            "X-Test-Status": String(status),
            "X-Test-Body": Data(body.utf8).base64EncodedString(),
            "X-Test-Offline": String(offline),
            "X-Test-Hold": String(hold)
        ]
        return UpdateService(session: URLSession(configuration: configuration), currentVersion: "2.3.5",
                             defaults: preferences.defaults, now: now)
    }

    @Test
    func newerReleaseOffersItsDownloadPage() async throws {
        let service = service(body: release("v2.4.0"))
        await service.checkForUpdates()
        guard case .available(let release) = service.result else {
            Issue.record("Expected an available update")
            return
        }
        #expect(release.tagName == "v2.4.0")
        #expect(release.releasePageURL?.host == "github.com")
        #expect(!service.isChecking)
    }

    @Test(arguments: ["2.3.5", "2.3.4"])
    func equalAndOlderReleasesDoNotOfferDowngrades(tag: String) async {
        let service = service(body: release(tag))
        await service.checkForUpdates()
        guard case .upToDate = service.result else {
            Issue.record("Expected the current version to be up to date")
            return
        }
        #expect(!service.isChecking)
    }

    @Test
    func missingReleaseIsNotReportedAsUpToDate() async {
        let service = service(status: 404)
        await service.checkForUpdates()
        guard case .noReleases = service.result else {
            Issue.record("Expected no releases")
            return
        }
        #expect(!service.isChecking)
    }

    @Test(arguments: [403, 429, 500])
    func httpErrorsAllowAnotherCheck(status: Int) async {
        let service = service(status: status)
        await service.checkForUpdates()
        guard case .failed(let message) = service.result else {
            Issue.record("Expected an HTTP error")
            return
        }
        #expect(message == (status == 500 ? UpdateError.httpStatus(status) : .rateLimited).localizedDescription)
        #expect(!service.isChecking)
        await service.checkForUpdates()
        #expect(!service.isChecking)
    }

    @Test(arguments: ["not json", "{}", "{\"tag_name\":\"2.4.0\"}"])
    func invalidResponsesFailClearly(body: String) async {
        let service = service(body: body)
        await service.checkForUpdates()
        guard case .failed(let message) = service.result else {
            Issue.record("Expected a response error")
            return
        }
        #expect(message == UpdateError.invalidResponse.localizedDescription)
        #expect(!service.isChecking)
    }

    @Test
    func invalidVersionFailsInsteadOfClaimingUpToDate() async {
        let service = service(body: release("latest"))
        await service.checkForUpdates()
        guard case .failed(let message) = service.result else {
            Issue.record("Expected a version error")
            return
        }
        #expect(message == UpdateError.invalidVersion.localizedDescription)
    }

    @Test(arguments: ["file:///tmp/installer", "https://example.com/download", "https://github.com/other/repo/releases/tag/v9"])
    func unexpectedReleasePagesAreRejected(page: String) async {
        let service = service(body: release("2.4.0", page: page))
        await service.checkForUpdates()
        guard case .failed = service.result else {
            Issue.record("Expected an invalid release page to be rejected")
            return
        }
    }

    @Test
    func offlineErrorsResetCheckingState() async {
        let service = service(offline: true)
        await service.checkForUpdates()
        guard case .failed = service.result else {
            Issue.record("Expected a network error")
            return
        }
        #expect(!service.isChecking)
    }

    @Test
    func repeatedClicksShareTheInFlightCheck() async {
        let service = service(hold: true)
        service.result = .upToDate
        let first = Task { await service.checkForUpdates() }
        while !service.isChecking { await Task.yield() }
        #expect(service.result == nil)
        await service.checkForUpdates()
        #expect(service.isChecking)
        first.cancel()
        await first.value
        #expect(!service.isChecking)
        #expect(service.result == nil)
    }

    @Test
    func automaticChecksDefaultToEnabledAndRememberTheSwitch() async {
        let service = service(body: release("2.4.0"))
        #expect(service.automaticallyChecksForUpdates)
        service.setAutomaticChecksEnabled(false)
        #expect(!self.service().automaticallyChecksForUpdates)
        await service.checkForUpdates(automatically: true)
        #expect(service.lastCheckDate == nil)
        #expect(service.availableRelease == nil)
        service.setAutomaticChecksEnabled(true)
        #expect(self.service().automaticallyChecksForUpdates)
        await service.checkForUpdates(automatically: true)
        #expect(service.availableRelease?.tagName == "2.4.0")
    }

    @Test(arguments: [200, 404, 403, 429, 500])
    func automaticChecksStayQuietWithoutANewVersion(status: Int) async {
        let service = service(body: release("2.3.5"), status: status)
        await service.checkForUpdates(automatically: true)
        #expect(service.result == nil)
        #expect(service.availableRelease == nil)
        #expect(service.lastCheckDate != nil)
        #expect(!service.isChecking)
    }

    @Test
    func automaticNetworkFailuresDoNotReplaceAnExistingManualAlert() async {
        let service = service(offline: true)
        service.result = .upToDate
        await service.checkForUpdates(automatically: true)
        guard case .upToDate = service.result else {
            Issue.record("A background failure must preserve the existing alert")
            return
        }
        #expect(!service.isChecking)
    }

    @Test
    func automaticUpdateWaitsForPresentationAndNotifiesOncePerVersion() async {
        let service = service(body: release("2.4.0"))
        await service.checkForUpdates(automatically: true)
        #expect(service.result == nil)
        #expect(service.availableRelease?.tagName == "2.4.0")
        service.presentAutomaticUpdateIfNeeded()
        guard case .available = service.result else {
            Issue.record("A visible window should be able to present the pending update")
            return
        }
        service.result = nil
        service.presentAutomaticUpdateIfNeeded()
        #expect(service.result == nil)
        let restarted = self.service()
        #expect(restarted.availableRelease?.tagName == "2.4.0")
        restarted.presentAutomaticUpdateIfNeeded()
        #expect(restarted.result == nil)
    }

    @Test
    func unpresentedUpdateSurvivesRestartAndInstalledUpdatesClearTheCache() async {
        let service = service(body: release("2.4.0"))
        await service.checkForUpdates(automatically: true)
        let restarted = self.service()
        #expect(restarted.availableRelease?.tagName == "2.4.0")
        restarted.presentAutomaticUpdateIfNeeded()
        guard case .available = restarted.result else {
            Issue.record("A cached update should remain available after restarting")
            return
        }
        let updated = UpdateService(currentVersion: "2.4.0", defaults: preferences.defaults)
        #expect(updated.availableRelease == nil)
    }

    @Test
    func disablingAutomaticChecksSuppressesPendingPrompts() async {
        let service = service(body: release("2.4.0"))
        await service.checkForUpdates(automatically: true)
        service.setAutomaticChecksEnabled(false)
        service.presentAutomaticUpdateIfNeeded()
        #expect(service.result == nil)
        // 关闭自动检查后，用户仍可以主动检查。
        await service.checkForUpdates()
        guard case .available = service.result else {
            Issue.record("Manual checks should work when automatic checks are disabled")
            return
        }
    }

    private final class TestClock {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
    }

    @Test
    func dailyIntervalSurvivesRestartAndManualChecksBypassIt() async {
        let clock = TestClock()
        let service = service(body: release("2.3.5"), now: { clock.date })
        let initialDate = clock.date
        await service.checkForUpdates(automatically: true)
        #expect(service.lastCheckDate == initialDate)
        clock.date.addTimeInterval(23 * 60 * 60)
        let restarted = self.service(body: release("2.3.5"), now: { clock.date })
        await restarted.checkForUpdates(automatically: true)
        #expect(restarted.lastCheckDate == initialDate)
        clock.date.addTimeInterval(60 * 60)
        await restarted.checkForUpdates(automatically: true)
        #expect(restarted.lastCheckDate == clock.date)
        #expect(restarted.result == nil)
        clock.date.addTimeInterval(1)
        await restarted.checkForUpdates()
        #expect(restarted.lastCheckDate == clock.date)
        guard case .upToDate = restarted.result else {
            Issue.record("Manual checks must bypass the daily interval")
            return
        }
    }

    @Test
    func backgroundFailureDoesNotRetryUntilTheNextDay() async {
        let clock = TestClock()
        let service = service(offline: true, now: { clock.date })
        await service.checkForUpdates(automatically: true)
        let attempted = service.lastCheckDate
        clock.date.addTimeInterval(60 * 60)
        await service.checkForUpdates(automatically: true)
        #expect(service.lastCheckDate == attempted)
        #expect(service.result == nil)
    }

    @Test
    func clockRollbackDoesNotBlockAutomaticChecksIndefinitely() async {
        let clock = TestClock()
        let service = service(body: release("2.3.5"), now: { clock.date })
        await service.checkForUpdates(automatically: true)
        clock.date.addTimeInterval(-60 * 60)
        await service.checkForUpdates(automatically: true)
        #expect(service.lastCheckDate == clock.date)
    }
}
