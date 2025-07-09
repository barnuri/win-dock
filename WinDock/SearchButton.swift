import SwiftUI
import AppKit

struct SearchButton: View {
    @AppStorage("searchAppChoice") private var searchAppChoice: SearchAppChoice = .spotlight
    var body: some View {
        Button(action: openSearch) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.gray.opacity(0.3)))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func openSearch() {
        switch searchAppChoice {
        case .spotlight:
            // Try Cmd+Space, then Cmd+Option+Space as fallback
            let scripts = [
                "tell application \"System Events\" to key code 49 using {command down}",
                "tell application \"System Events\" to key code 49 using {command down, option down}"
            ]
            var success = false
            for src in scripts {
                if let script = NSAppleScript(source: src) {
                    var error: NSDictionary?
                    script.executeAndReturnError(&error)
                    if error == nil {
                        success = true
                        break
                    }
                }
            }
            if !success {
                AppLogger.shared.error("Failed to trigger Spotlight with AppleScript")
            }
        case .raycast:
            let bundleID = "com.raycast.macos"
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                    if let error = error {
                        AppLogger.shared.error("Failed to launch Raycast: \(error.localizedDescription)")
                    }
                }
            } else {
                AppLogger.shared.error("Raycast app not found")
            }
        case .alfred:
            let bundleID = "com.runningwithcrayons.Alfred"
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                    if let error = error {
                        AppLogger.shared.error("Failed to launch Alfred: \(error.localizedDescription)")
                    }
                }
            } else {
                AppLogger.shared.error("Alfred app not found")
            }
        }
    }
}