import SwiftUI
import AppKit

struct AboutView: View {
    @StateObject var engine = MyEngine.shared
    @StateObject var updateService = UpdateService.shared
    @State private var showingUpdateAlert = false
    @State private var updateAlertTitle = ""
    @State private var updateAlertMessage = ""
    @State private var hasUpdate = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 16) {
                if let appIcon = NSImage(contentsOfFile: Bundle.main.path(forResource: "AppIcon", ofType: "png") ?? "") {
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
            
            VStack(spacing: 10) {
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
                
                Button(action: openLicense) {
                    Text(NSLocalizedString("about.license", comment: ""))
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
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
        .alert(updateAlertTitle, isPresented: $showingUpdateAlert) {
            if hasUpdate {
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
    
    private func checkForUpdates() {
        updateService.checkForUpdates { result in
            switch result {
            case .success(let release):
                if let release = release {
                    if updateService.isNewerVersion(release.tagName) {
                        hasUpdate = true
                        updateAlertTitle = NSLocalizedString("update.available.title", comment: "")
                        updateAlertMessage = String(format: NSLocalizedString("update.available.message", comment: ""), release.tagName, updateService.currentVersion)
                    } else {
                        hasUpdate = false
                        updateAlertTitle = NSLocalizedString("update.latest.title", comment: "")
                        updateAlertMessage = NSLocalizedString("update.latest.message", comment: "")
                    }
                } else {
                    hasUpdate = false
                    updateAlertTitle = NSLocalizedString("update.latest.title", comment: "")
                    updateAlertMessage = NSLocalizedString("update.latest.message", comment: "")
                }
                showingUpdateAlert = true
                
            case .failure(let error):
                hasUpdate = false
                updateAlertTitle = NSLocalizedString("update.error.title", comment: "")
                updateAlertMessage = error.localizedDescription
                showingUpdateAlert = true
            }
        }
    }
    
    private func openLicense() {
        if let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openSupport() {
        openURL("https://github.com/baikaihao/KeyMapper/issues/new")
    }
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
