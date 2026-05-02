import Foundation
import Combine
import AppKit

// MARK: - GitHubRelease
// GitHub Release API 响应数据模型，对应 /repos/{owner}/{repo}/releases/latest 的返回结构

struct GitHubRelease: Codable {
    // 版本标签，如 "v1.2.0"
    let tagName: String
    // Release 标题
    let name: String
    // Release 描述正文
    let body: String
    // Release 页面 URL
    let htmlUrl: String
    // Release 附带的资源文件列表
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case assets
    }
}

// MARK: - GitHubAsset
// GitHub Release 中的资源文件模型（如 .dmg 安装包）

struct GitHubAsset: Codable {
    // 资源文件名
    let name: String
    // 资源下载 URL
    let browserDownloadUrl: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}

// MARK: - UpdateService
// GitHub Release 更新检查服务（单例）。
// 通过 GitHub API 检查最新版本，并与当前版本进行语义化版本比较。

class UpdateService: ObservableObject {
    static let shared = UpdateService()

    // 是否正在检查更新
    @Published var isChecking = false
    // 最新 Release 信息
    @Published var latestRelease: GitHubRelease?
    // 错误信息
    @Published var errorMessage: String?

    // GitHub 仓库所有者
    private let repoOwner = "baikaihao"
    // GitHub 仓库名称
    private let repoName = "KeyMapper"

    // 当前应用版本号（从 Info.plist 读取）
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // 当前构建号（从 Info.plist 读取）
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - 更新检查

    // 通过 GitHub API 检查最新版本。
    // 请求 /repos/{owner}/{repo}/releases/latest 接口，
    // 解析响应并与当前版本比较。
    func checkForUpdates(completion: @escaping (Result<GitHubRelease?, Error>) -> Void) {
        isChecking = true
        errorMessage = nil

        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            completion(.failure(UpdateError.invalidURL))
            isChecking = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isChecking = false

                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(.failure(UpdateError.invalidResponse))
                    return
                }

                // 404 表示还没有 Release
                if httpResponse.statusCode == 404 {
                    completion(.success(nil))
                    return
                }

                guard httpResponse.statusCode == 200, let data = data else {
                    completion(.failure(UpdateError.invalidResponse))
                    return
                }

                do {
                    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                    self?.latestRelease = release
                    completion(.success(release))
                } catch {
                    self?.errorMessage = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - 版本比较

    // 语义化版本比较：判断远程版本是否比当前版本更新。
    // 支持去除 "v" 前缀，按 "." 分隔后逐段比较数字大小。
    // 例如 "1.3.0" > "1.2.5" → true
    func isNewerVersion(_ remoteVersion: String) -> Bool {
        let current = currentVersion.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        let remote = remoteVersion.trimmingCharacters(in: CharacterSet(charactersIn: "v"))

        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(currentParts.count, remoteParts.count)

        for i in 0..<maxCount {
            let currentPart = i < currentParts.count ? currentParts[i] : 0
            let remotePart = i < remoteParts.count ? remoteParts[i] : 0

            if remotePart > currentPart {
                return true
            } else if remotePart < currentPart {
                return false
            }
        }

        return false
    }

    // MARK: - 下载/打开页面

    // 在浏览器中打开 Release 页面，优先打开最新 Release 页面，否则打开仓库 Releases 列表
    func openReleasePage() {
        if let release = latestRelease {
            if let url = URL(string: release.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
        } else {
            if let url = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - UpdateError
// 更新检查错误类型

enum UpdateError: Error, LocalizedError {
    case invalidURL
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("update.error.invalid.url", comment: "")
        case .invalidResponse:
            return NSLocalizedString("update.error.invalid.response", comment: "")
        }
    }
}
