import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - BlacklistView
// 黑名单应用管理页面。
// 展示已加入黑名单的应用列表（显示应用图标、名称、Bundle ID），
// 支持通过 NSOpenPanel 选择 .app 文件添加，支持删除。
// 黑名单中的应用在前台时不会触发键盘映射。

struct BlacklistView: View {
    @StateObject var engine = MyEngine.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(NSLocalizedString("blacklist.title", comment: ""))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Text(NSLocalizedString("blacklist.desc", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                // 黑名单应用列表
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(engine.blacklist, id: \.self) { bundleId in
                            BlacklistItemRow(bundleId: bundleId) {
                                engine.blacklist.removeAll { $0 == bundleId }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            Divider()

            // 添加应用按钮
            HStack {
                Spacer()
                Button(action: addApp) {
                    Label(NSLocalizedString("blacklist.add", comment: ""), systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    // 通过 NSOpenPanel 选择 .app 文件添加到黑名单。
    // 从选中应用的 Bundle 中提取 bundleIdentifier 作为黑名单标识。
    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = NSLocalizedString("blacklist.select.app", comment: "")

        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url),
               let bundleId = bundle.bundleIdentifier {
                // 避免重复添加
                if !engine.blacklist.contains(bundleId) {
                    engine.blacklist.append(bundleId)
                }
            }
        }
    }
}

// MARK: - BlacklistItemRow
// 黑名单应用行组件，显示应用图标、名称、Bundle ID 和删除按钮

struct BlacklistItemRow: View {
    // 应用的 Bundle Identifier
    let bundleId: String
    // 删除回调
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // 应用图标：优先从系统获取，失败则显示占位图标
            if let icon = getAppIcon(for: bundleId) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 36, height: 36)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }

            // 应用名称和 Bundle ID
            VStack(alignment: .leading, spacing: 2) {
                Text(getAppName(for: bundleId))
                    .font(.system(size: 13, weight: .medium))
                Text(bundleId)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 删除按钮
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // 通过 Bundle ID 查找应用并获取显示名称
    private func getAppName(for bundleId: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        return bundleId
    }

    // 通过 Bundle ID 获取应用图标
    private func getAppIcon(for bundleId: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
}
