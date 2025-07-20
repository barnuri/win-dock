import SwiftUI
import SettingsAccess

// Helper to open settings from AppKit code
class SettingsHelper: ObservableObject {
    static let shared = SettingsHelper()
    
    @Published var shouldOpenSettings = false
    
    private init() {}
    
    func requestOpenSettings() {
        DispatchQueue.main.async {
            self.shouldOpenSettings = true
        }
    }
}

// SwiftUI view that handles the actual settings opening
struct SettingsAccessHelper: View {
    @Environment(\.openSettingsLegacy) private var openSettingsLegacy
    @ObservedObject private var helper = SettingsHelper.shared
    
    private func bringSettingsToFront() {
        // Get the current app (WinDock) and bring it to front
        let currentApp = NSRunningApplication.current
        
        // Activate WinDock to ensure settings window is in the foreground
        if #available(macOS 14.0, *) {
            currentApp.activate()
        } else {
            currentApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
        
        // Use AppleScript to ensure the settings window is brought to the very front
        let bringToFrontScript = """
        tell application "System Events"
            tell process "WinDock"
                set frontmost to true
                try
                    tell window 1
                        perform action "AXRaise"
                        set value of attribute "AXMain" to true
                        set value of attribute "AXFocused" to true
                    end tell
                end try
            end tell
        end tell
        """
        
        if let appleScript = NSAppleScript(source: bringToFrontScript) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                AppLogger.shared.error("Bring settings to front AppleScript error: \(error)")
            } else {
                AppLogger.shared.info("Successfully brought settings window to front")
            }
        }
    }
    
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(helper.$shouldOpenSettings) { shouldOpen in
                if shouldOpen {
                    do {
                        try openSettingsLegacy()
                        AppLogger.shared.info("Settings opened successfully via SettingsAccess")
                        
                        // Ensure settings window comes to front and stays on top
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.bringSettingsToFront()
                        }
                        
                        // Additional attempt after a longer delay to ensure it's truly on top
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.bringSettingsToFront()
                        }
                    } catch {
                        AppLogger.shared.error("Failed to open settings via SettingsAccess: \(error)")
                    }
                    helper.shouldOpenSettings = false
                }
            }
    }
}
