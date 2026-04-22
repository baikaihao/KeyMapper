import Foundation
import Combine
import AppKit

struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let body: String
    let htmlUrl: String
    let assets: [GitHubAsset]
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}

class UpdateService: ObservableObject {
    static let shared = UpdateService()
    
    @Published var isChecking = false
    @Published var latestRelease: GitHubRelease?
    @Published var errorMessage: String?
    
    private let repoOwner = "baikaihao"
    private let repoName = "KeyMapper"
    
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
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
