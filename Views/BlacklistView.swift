import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BlacklistView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject var engine = MyEngine.shared
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(NSLocalizedString("app.blacklist", comment: ""))
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("app.blacklist.desc", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if engine.blacklist.isEmpty {
                    Text(NSLocalizedString("app.blacklist.empty", comment: ""))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    List {
                        ForEach(engine.blacklist, id: \.self) { bundleId in
                            HStack {
                                Text(getAppName(for: bundleId))
                                    .font(.system(size: 12))
                                Spacer()
                                Button(action: {
                                    engine.blacklist.removeAll { $0 == bundleId }
                                }) {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 150)
                }
            }
            
            HStack {
                Spacer()
                Button(action: addApp) {
                    Label(NSLocalizedString("app.blacklist.add", comment: ""), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 350, height: 350)
    }
    
    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = NSLocalizedString("app.blacklist.select", comment: "")
        
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url),
               let bundleId = bundle.bundleIdentifier {
                if !engine.blacklist.contains(bundleId) {
                    engine.blacklist.append(bundleId)
                }
            }
        }
    }
    
    private func getAppName(for bundleId: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        return bundleId
    }
}
