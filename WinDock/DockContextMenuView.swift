import SwiftUI
import AppKit

struct DockContextMenuView: View {
    let appManager: AppManager
    @StateObject private var visibilityManager = DockVisibilityManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(visibilityManager.visibilityDisplayName) {
                visibilityManager.toggleVisibility()
            }
            
            Divider()
            
            Button("Show Desktop") {
                showDesktop()
            }
            
            Button("Task Manager") {
                openActivityMonitor()
            }
            
            Divider()
            
            Button("Settings...") {
                openSettings()
            }
            
            Divider()
            
            Button("Restart WinDock") {
                restartWinDock()
            }
            
            Button("Quit WinDock") {
                quitWinDock()
            }
            
            Divider()
            
            Button("Lock") {
                lockScreen()
            }
            
            Button("Sleep") {
                sleep()
            }
            
            Divider()
            
            Button("Close All Windows") {
                closeAllWindows()
            }
            
            Button("Hide All Windows") {
                hideAllWindows()
            }
        }
    }
    
    private func showDesktop() {
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            guard let bundleIdentifier = app.bundleIdentifier else { continue }
            
            // Skip system apps and WinDock itself
            if bundleIdentifier.contains("WinDock") {
                continue
            }
            
            // Hide the application
            app.hide()
        }
    }
    
    private func openActivityMonitor() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
    
    private func openSettings() {
        AppLogger.shared.info("Opening settings from DockContextMenuView")
        SettingsHelper.shared.requestOpenSettings()
    }
    
    private func restartWinDock() {
        AppLogger.shared.info("Restarting WinDock from dock context menu")
        restartApplication()
    }
    
    private func quitWinDock() {
        NSApplication.shared.terminate(nil)
    }
    
    private func lockScreen() {
        executeAppleScript("""
        tell application "System Events"
            keystroke "q" using {control down, command down}
        end tell
        """)
    }
    
    private func sleep() {
        executeAppleScript("""
        tell application "System Events"
            sleep
        end tell
        """)
    }
    
    private func closeAllWindows() {
        // Use NSWorkspace to get running apps and close them
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            guard let bundleIdentifier = app.bundleIdentifier else { continue }
            
            // Skip system apps and WinDock itself
            if bundleIdentifier.contains("WinDock") || 
               app.activationPolicy != .regular {
                continue
            }
            
            // Terminate the application (this will close all windows)
            app.terminate()
        }
    }
    
    private func hideAllWindows() {
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            guard let bundleIdentifier = app.bundleIdentifier else { continue }
            
            // Skip system apps and WinDock itself
            if bundleIdentifier.contains("WinDock") || 
               app.activationPolicy != .regular {
                continue
            }
            
            // Hide the application
            app.hide()
        }
    }
    
    private func restartApplication() {
        let appPath = Bundle.main.bundlePath
        let relaunchPath = "/usr/bin/open"
        
        // Create a task to relaunch the app
        let task = Process()
        task.executableURL = URL(fileURLWithPath: relaunchPath)
        task.arguments = ["-n", appPath]
        
        do {
            try task.run()
            // Quit current instance after launching new one
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            AppLogger.shared.error("Failed to restart application: \(error)")
        }
    }
    
    @discardableResult
    private func executeAppleScript(_ script: String) -> Bool {
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var error: NSDictionary?
        _ = appleScript.executeAndReturnError(&error)
        if let error = error {
            AppLogger.shared.error("AppleScript error: \(error)")
            return false
        }
        return true
    }
}

#Preview {
    DockContextMenuView(appManager: AppManager())
}
