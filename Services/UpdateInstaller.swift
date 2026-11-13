import Foundation
import CryptoKit
import Security

nonisolated struct PreparedUpdate: Sendable {
    let release: GitHubRelease
    let directory: URL
    let appURL: URL
}

nonisolated struct UpdateInstallPlan: Codable, Sendable {
    let workspace: URL
    let destination: URL
    let downloadDirectory: URL

    var stagedApp: URL { workspace.appendingPathComponent("KeyMapper.app") }
    var backupApp: URL { workspace.appendingPathComponent("Previous.app") }
    var statusURL: URL { workspace.appendingPathComponent("status") }
    var scriptURL: URL { workspace.appendingPathComponent("install.sh") }

    func process(parentPID: Int32 = ProcessInfo.processInfo.processIdentifier,
                 launcher: String = "/usr/bin/open") throws -> Process {
        let inode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? NSNumber
        guard let inode else { throw UpdateInstallationError.cannotInstall }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path, String(parentPID), stagedApp.path, destination.path,
                             backupApp.path, statusURL.path, launcher, inode.stringValue]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }

    // 所有路径作为参数传入，不能把应用安装路径拼接为 shell 代码。
    static let helperScript = #"""
    #!/bin/sh
    set -u
    parent_pid="$1"
    staged="$2"
    destination="$3"
    backup="$4"
    status="$5"
    launcher="$6"
    expected_inode="$7"
    count=0
    while /bin/kill -0 "$parent_pid" 2>/dev/null; do
        count=$((count + 1))
        if [ "$count" -ge 60 ]; then
            /usr/bin/printf 'cancelled' > "$status"
            exit 1
        fi
        /bin/sleep 1
    done
    # 用户可能在等待退出期间移动了应用，此时不能替换另一个目录。
    if [ -L "$destination" ] || [ ! -d "$staged" ] ||
       [ "$(/usr/bin/stat -f '%i' "$destination" 2>/dev/null)" != "$expected_inode" ]; then
        /usr/bin/printf 'failed' > "$status"
        exit 1
    fi
    if ! /bin/mv "$destination" "$backup"; then
        /usr/bin/printf 'failed' > "$status"
        "$launcher" -n "$destination"
        exit 1
    fi
    if /bin/mv "$staged" "$destination"; then
        # 新进程启动时才能清理备份，因此先写入交接状态。
        /usr/bin/printf 'success' > "$status"
        if "$launcher" -n "$destination"; then
            exit 0
        fi
        /usr/bin/printf 'failed' > "$status"
        /bin/mv "$destination" "$staged" || exit 1
    fi
    /usr/bin/printf 'failed' > "$status"
    if /bin/mv "$backup" "$destination"; then
        "$launcher" -n "$destination"
    else
        # 极端情况下保留两份应用，仍尝试打开原版本。
        "$launcher" -n "$backup"
    fi
    exit 1
    """#
}

// 网络、解压、校验和复制都在并发执行器中进行，避免阻塞按键处理和界面。
nonisolated struct UpdateInstaller: Sendable {
    let session: URLSession
    let installedAppURL: URL
    let currentVersion: String

    @concurrent
    func prepare(_ release: GitHubRelease) async throws -> PreparedUpdate {
        guard let asset = release.installableAsset else { throw UpdateInstallationError.unsupportedPackage }
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("KeyMapperUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        do {
            var request = URLRequest(url: asset.downloadURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
            request.setValue("KeyMapper/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (download, response) = try await session.download(for: request)
            defer { try? FileManager.default.removeItem(at: download) }
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw UpdateInstallationError.downloadFailed
            }
            let archive = directory.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: download, to: archive)
            try Self.verifyArchive(archive, asset: asset)
            let entries = try Self.run("/usr/bin/unzip", ["-Z", "-1", archive.path])
            guard Self.hasSafeArchivePaths(entries) else { throw UpdateInstallationError.invalidPackage }
            let extracted = directory.appendingPathComponent("extracted")
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: false)
            // bsdtar 的默认保护会拒绝穿越目录、绝对路径和通过符号链接写入目录之外。
            _ = try Self.run("/usr/bin/tar", ["-xf", archive.path, "-C", extracted.path])
            try Task.checkCancellation()
            let app = extracted.appendingPathComponent("KeyMapper.app")
            try Self.validateApp(app, release: release, currentVersion: currentVersion,
                                 installedAppURL: installedAppURL)
            try FileManager.default.removeItem(at: archive)
            return PreparedUpdate(release: release, directory: directory, appURL: app)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    @concurrent
    func stage(_ update: PreparedUpdate) async throws -> UpdateInstallPlan {
        let destination = installedAppURL.resolvingSymlinksInPath()
        let parent = destination.deletingLastPathComponent()
        let values = try destination.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        guard destination.pathExtension == "app", !destination.path.contains("/AppTranslocation/"),
              values.volumeIsReadOnly != true, FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateInstallationError.cannotInstall
        }
        // 与目标应用同卷，退出后只做目录重命名，不直接覆盖运行中的可执行文件。
        let plan = UpdateInstallPlan(workspace: parent.appendingPathComponent(".KeyMapper-update-\(UUID().uuidString)"),
                                     destination: destination, downloadDirectory: update.directory)
        try FileManager.default.createDirectory(at: plan.workspace, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        do {
            try FileManager.default.copyItem(at: update.appURL, to: plan.stagedApp)
            try Self.validateApp(plan.stagedApp, release: update.release, currentVersion: currentVersion,
                                 installedAppURL: destination)
            try Task.checkCancellation()
            try UpdateInstallPlan.helperScript.write(to: plan.scriptURL, atomically: true, encoding: .utf8)
            return plan
        } catch {
            try? FileManager.default.removeItem(at: plan.workspace)
            throw error
        }
    }

    static func verifyArchive(_ archive: URL, asset: GitHubReleaseAsset) throws {
        let size = try FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? NSNumber
        guard size?.int64Value == asset.size, let expectedHash = asset.sha256 else {
            throw UpdateInstallationError.checksumMismatch
        }
        let file = try FileHandle(forReadingFrom: archive)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        let actualHash = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actualHash == expectedHash else { throw UpdateInstallationError.checksumMismatch }
    }

    static func hasSafeArchivePaths(_ listing: String) -> Bool {
        let entries = listing.split(separator: "\n")
        return !entries.isEmpty && entries.allSatisfy {
            !$0.hasPrefix("/") && !$0.contains("\\") && !$0.split(separator: "/").contains("..")
        }
    }

    static func validateApp(_ appURL: URL, release: GitHubRelease, currentVersion: String,
                            installedAppURL: URL) throws {
        let root = appURL.resolvingSymlinksInPath()
        guard root == appURL.standardizedFileURL, let bundle = Bundle(url: root),
              bundle.bundleIdentifier == "bkh.KeyMapper",
              let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
              let remote = UpdateVersion(release.tagName), let downloaded = UpdateVersion(version),
              let current = UpdateVersion(currentVersion), downloaded == remote, downloaded > current,
              let executable = bundle.executableURL,
              executable.resolvingSymlinksInPath().path.hasPrefix(root.path + "/"),
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw UpdateInstallationError.invalidPackage
        }
        if let minimum = bundle.infoDictionary?["LSMinimumSystemVersion"] as? String {
            let components = minimum.split(separator: ".", omittingEmptySubsequences: false)
            let parts = components.compactMap { Int($0) }
            guard !parts.isEmpty, parts.count <= 3, parts.count == components.count,
                  parts.allSatisfy({ $0 >= 0 }) else { throw UpdateInstallationError.invalidPackage }
            let version = OperatingSystemVersion(majorVersion: parts[0], minorVersion: parts.count > 1 ? parts[1] : 0,
                                                 patchVersion: parts.count > 2 ? parts[2] : 0)
            guard ProcessInfo.processInfo.isOperatingSystemAtLeast(version) else {
                throw UpdateInstallationError.incompatibleSystem
            }
        }
        let architectures = try run("/usr/bin/lipo", ["-archs", executable.path]).split(whereSeparator: \.isWhitespace)
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        guard architectures.contains(Substring(architecture)) else { throw UpdateInstallationError.incompatibleSystem }

        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(root as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateInstallationError.invalidSignature
        }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else {
            throw UpdateInstallationError.invalidSignature
        }
        // Developer ID 发布版本继续要求相同签名身份；现有 ad-hoc 发布包依靠 GitHub 的 SHA-256 校验。
        var installedCode: SecStaticCode?
        var information: CFDictionary?
        guard SecStaticCodeCreateWithPath(installedAppURL as CFURL, [], &installedCode) == errSecSuccess,
              let installedCode,
              SecCodeCopySigningInformation(installedCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any] else {
            throw UpdateInstallationError.invalidSignature
        }
        if information[kSecCodeInfoTeamIdentifier as String] != nil {
            var requirement: SecRequirement?
            guard SecCodeCopyDesignatedRequirement(installedCode, [], &requirement) == errSecSuccess,
                  let requirement, SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
                throw UpdateInstallationError.invalidSignature
            }
        }
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateInstallationError.invalidPackage }
        return String(decoding: data, as: UTF8.self)
    }
}

nonisolated enum UpdateInstallationError: LocalizedError {
    case unsupportedPackage, downloadFailed, checksumMismatch, invalidPackage, invalidSignature
    case incompatibleSystem, cannotInstall, installationFailed

    var errorDescription: String? {
        let key: String
        switch self {
        case .unsupportedPackage: key = "update.install.error.unsupported"
        case .downloadFailed: key = "update.install.error.download"
        case .checksumMismatch: key = "update.install.error.checksum"
        case .invalidPackage: key = "update.install.error.package"
        case .invalidSignature: key = "update.install.error.signature"
        case .incompatibleSystem: key = "update.install.error.system"
        case .cannotInstall: key = "update.install.error.location"
        case .installationFailed: key = "update.install.error.failed"
        }
        return NSLocalizedString(key, comment: "")
    }
}
