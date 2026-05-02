import SwiftUI
import AppKit

// MARK: - AboutView
// 关于页面。
// 展示应用图标（支持深色模式）、版本号、构建号。
// 提供"检查更新"按钮（调用 UpdateService）、"查看许可证"按钮、GitHub 链接和 Issues 反馈入口。

struct AboutView: View {
    @StateObject var engine = MyEngine.shared
    @StateObject var updateService = UpdateService.shared
    @State private var showingUpdateAlert = false
    @State private var updateAlertTitle = ""
    @State private var updateAlertMessage = ""
    // 是否检测到新版本
    @State private var hasUpdate = false
    @Environment(\.colorScheme) var colorScheme

    // 根据当前色彩模式加载对应的应用图标
    var appIcon: NSImage? {
        let iconName = colorScheme == .dark ? "AppIcon-Dark" : "AppIcon"
        return NSImage(contentsOfFile: Bundle.main.path(forResource: iconName, ofType: "png") ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // 应用图标和版本信息
            VStack(spacing: 16) {
                if let appIcon = appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .cornerRadius(22)
                } else {
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.white)
                        .frame(width: 96, height: 96)
                        .background(Color.accentColor)
                        .cornerRadius(22)
                }

                VStack(spacing: 4) {
                    Text("KeyMapper")
                        .font(.system(size: 24, weight: .bold))
                    Text(updateService.currentVersion)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Build \(updateService.buildNumber)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            // 操作按钮组
            VStack(spacing: 10) {
                // 检查更新按钮：检查期间显示加载指示器
                Button(action: checkForUpdates) {
                    HStack {
                        if updateService.isChecking {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        }
                        Text(NSLocalizedString("about.check.update", comment: ""))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(updateService.isChecking)

                // 查看许可证按钮
                Button(action: openLicense) {
                    Text(NSLocalizedString("about.license", comment: ""))
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                // 问题反馈按钮
                Button(action: openSupport) {
                    Text(NSLocalizedString("about.support", comment: ""))
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .frame(width: 200)
            .padding(.top, 32)

            Spacer()

            // GitHub 仓库链接按钮
            Button(action: { openURL("https://github.com/baikaihao/KeyMapper/") }) {
                if let githubIcon = NSImage(contentsOfFile: Bundle.main.path(forResource: "GitHub_Invertocat_Black", ofType: "svg") ?? "") {
                    Image(nsImage: githubIcon)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "link")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 更新检查结果弹窗
        .alert(updateAlertTitle, isPresented: $showingUpdateAlert) {
            if hasUpdate {
                // 有新版本时提供下载按钮
                Button(NSLocalizedString("update.download", comment: "")) {
                    updateService.openReleasePage()
                }
                Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            } else {
                Button(NSLocalizedString("ok", comment: ""), role: .cancel) {}
            }
        } message: {
            Text(updateAlertMessage)
        }
    }

    // MARK: - 更新检查

    // 调用 UpdateService 检查更新，根据结果显示不同弹窗
    private func checkForUpdates() {
        updateService.checkForUpdates { result in
            switch result {
            case .success(let release):
                if let release = release {
                    if updateService.isNewerVersion(release.tagName) {
                        // 发现新版本
                        hasUpdate = true
                        updateAlertTitle = NSLocalizedString("update.available.title", comment: "")
                        updateAlertMessage = String(format: NSLocalizedString("update.available.message", comment: ""), release.tagName, updateService.currentVersion)
                    } else {
                        // 已是最新版本
                        hasUpdate = false
                        updateAlertTitle = NSLocalizedString("update.latest.title", comment: "")
                        updateAlertMessage = NSLocalizedString("update.latest.message", comment: "")
                    }
                } else {
                    // 没有 Release
                    hasUpdate = false
                    updateAlertTitle = NSLocalizedString("update.latest.title", comment: "")
                    updateAlertMessage = NSLocalizedString("update.latest.message", comment: "")
                }
                showingUpdateAlert = true

            case .failure(let error):
                // 检查失败
                hasUpdate = false
                updateAlertTitle = NSLocalizedString("update.error.title", comment: "")
                updateAlertMessage = error.localizedDescription
                showingUpdateAlert = true
            }
        }
    }

    // MARK: - 外部链接

    // 打开本地 LICENSE 文件
    private func openLicense() {
        if let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil) {
            NSWorkspace.shared.open(url)
        }
    }

    // 打开 GitHub Issues 页面
    private func openSupport() {
        openURL("https://github.com/baikaihao/KeyMapper/issues/new")
    }

    // 在默认浏览器中打开指定 URL
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
