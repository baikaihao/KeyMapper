import Foundation
import Testing
@testable import KeyMapperCore

@Suite @MainActor
struct UpdateInstallerTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("KeyMapperInstallerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func release(assets: [GitHubReleaseAsset] = []) -> GitHubRelease {
        GitHubRelease(tagName: "v2.4.2", htmlUrl: URL(string: "https://github.com/baikaihao/KeyMapper/releases/tag/v2.4.2")!, assets: assets)
    }

    private func asset(name: String = "KeyMapper.app.zip", size: Int64 = 3,
                       url: String = "https://github.com/baikaihao/KeyMapper/releases/download/v2.4.2/KeyMapper.app.zip",
                       digest: String? = "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") -> GitHubReleaseAsset {
        GitHubReleaseAsset(name: name, size: size, downloadURL: URL(string: url)!, digest: digest)
    }

    @Test
    func oldCachedReleasesStillDecodeWithoutAttachments() throws {
        let data = Data(#"{"tag_name":"2.4.1","html_url":"https://github.com/baikaihao/KeyMapper/releases/tag/2.4.1"}"#.utf8)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        #expect(release.assets.isEmpty)
        #expect(release.installableAsset == nil)
    }

    @Test
    func onlyMatchingRepositoryPackagesWithChecksumsCanInstall() {
        #expect(release(assets: [asset()]).installableAsset != nil)
        let unsafe = [
            asset(name: "Source.zip"), asset(size: 0), asset(size: 300 * 1024 * 1024),
            asset(url: "https://example.com/KeyMapper.app.zip"),
            asset(url: "http://github.com/baikaihao/KeyMapper/releases/download/v2.4.2/KeyMapper.app.zip"),
            asset(url: "https://github.com/other/KeyMapper/releases/download/v2.4.2/KeyMapper.app.zip"),
            asset(url: "https://github.com/baikaihao/KeyMapper/releases/download/v9/KeyMapper.app.zip"),
            asset(digest: nil), asset(digest: "sha256:bad"), asset(digest: "md5:abc")
        ]
        for attachment in unsafe {
            #expect(release(assets: [attachment]).installableAsset == nil)
        }
    }

    @Test
    func corruptedOrTruncatedDownloadsAreRejected() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("download.zip")
        try Data("abc".utf8).write(to: file)
        try UpdateInstaller.verifyArchive(file, asset: asset())
        try Data("abd".utf8).write(to: file)
        #expect(throws: (any Error).self) { try UpdateInstaller.verifyArchive(file, asset: asset()) }
        try Data("ab".utf8).write(to: file)
        #expect(throws: (any Error).self) { try UpdateInstaller.verifyArchive(file, asset: asset()) }
    }

    @Test(arguments: ["/tmp/evil", "KeyMapper.app/../../evil", "../KeyMapper.app", "KeyMapper.app/..\\evil", ""])
    func archiveTraversalPathsAreRejected(path: String) {
        #expect(!UpdateInstaller.hasSafeArchivePaths(path))
    }

    @Test
    func anotherAppOrWrongVersionCannotReplaceKeyMapper() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for (identifier, version) in [("other.App", "2.4.2"), ("bkh.KeyMapper", "2.4.1"), ("bkh.KeyMapper", "9.0.0")] {
            let app = directory.appendingPathComponent("\(UUID().uuidString).app")
            let contents = app.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": version,
                                       "CFBundleExecutable": "KeyMapper", "CFBundlePackageType": "APPL"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            #expect(throws: (any Error).self) {
                try UpdateInstaller.validateApp(app, release: release(), currentVersion: "2.4.1", installedAppURL: app)
            }
        }
    }

    private func plan(in directory: URL) throws -> UpdateInstallPlan {
        // 包含 shell 特殊字符的路径也必须原样处理。
        let destination = directory.appendingPathComponent("KeyMapper ' $(echo injected).app")
        let workspace = directory.appendingPathComponent("workspace")
        let plan = UpdateInstallPlan(workspace: workspace, destination: destination, downloadDirectory: directory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: plan.stagedApp, withIntermediateDirectories: true)
        try "old".write(to: destination.appendingPathComponent("version"), atomically: true, encoding: .utf8)
        try "new".write(to: plan.stagedApp.appendingPathComponent("version"), atomically: true, encoding: .utf8)
        try UpdateInstallPlan.helperScript.write(to: plan.scriptURL, atomically: true, encoding: .utf8)
        return plan
    }

    @Test
    func successfulInstallationKeepsBackupUntilNewAppStarts() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plan = try plan(in: directory)
        let process = try plan.process(parentPID: 2_000_000_000, launcher: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(try String(contentsOf: plan.destination.appendingPathComponent("version"), encoding: .utf8) == "new")
        #expect(try String(contentsOf: plan.backupApp.appendingPathComponent("version"), encoding: .utf8) == "old")
        #expect(try String(contentsOf: plan.statusURL, encoding: .utf8) == "success")
    }

    @Test
    func failedRelaunchRestoresThePreviousApp() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plan = try plan(in: directory)
        let process = try plan.process(parentPID: 2_000_000_000, launcher: "/usr/bin/false")
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus != 0)
        #expect(try String(contentsOf: plan.destination.appendingPathComponent("version"), encoding: .utf8) == "old")
        #expect(try String(contentsOf: plan.statusURL, encoding: .utf8) == "failed")
    }

    @Test
    func helperWaitsForRunningAppToExit() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plan = try plan(in: directory)
        let runningApp = Process()
        runningApp.executableURL = URL(fileURLWithPath: "/bin/sleep")
        runningApp.arguments = ["10"]
        try runningApp.run()
        defer { if runningApp.isRunning { runningApp.terminate() } }
        let helper = try plan.process(parentPID: runningApp.processIdentifier, launcher: "/usr/bin/true")
        try helper.run()
        try await Task.sleep(for: .milliseconds(100))
        #expect(helper.isRunning)
        #expect(try String(contentsOf: plan.destination.appendingPathComponent("version"), encoding: .utf8) == "old")
        runningApp.terminate()
        runningApp.waitUntilExit()
        helper.waitUntilExit()
        #expect(helper.terminationStatus == 0)
    }

    @Test
    func movedInstallationIsNotReplaced() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plan = try plan(in: directory)
        let helper = try plan.process(parentPID: 2_000_000_000, launcher: "/usr/bin/true")
        try FileManager.default.moveItem(at: plan.destination, to: directory.appendingPathComponent("Moved.app"))
        try FileManager.default.createDirectory(at: plan.destination, withIntermediateDirectories: false)
        try helper.run()
        helper.waitUntilExit()
        #expect(helper.terminationStatus != 0)
        #expect(!FileManager.default.fileExists(atPath: plan.destination.appendingPathComponent("version").path))
        #expect(try String(contentsOf: directory.appendingPathComponent("Moved.app/version"), encoding: .utf8) == "old")
    }
}
