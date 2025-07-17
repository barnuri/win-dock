import SwiftUI
import AppKit

struct DockContextMenuView: View {
    let appManager: AppManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.openSettings()
        }
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
