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
        executeAppleScript("""
        tell application "System Events"
            key code 103 using {command down}
        end tell
        """)
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
        executeAppleScript("""
        tell application "System Events"
            set allProcesses to every process whose visible is true
            repeat with currentProcess in allProcesses
                if name of currentProcess is not "WinDock" and name of currentProcess is not "Finder" and name of currentProcess is not "System Events" then
                    try
                        click button 1 of every window of currentProcess
                    end try
                end if
            end repeat
        end tell
        """)
    }
    
    private func hideAllWindows() {
        executeAppleScript("""
        tell application "System Events"
            set allProcesses to every process whose visible is true
            repeat with currentProcess in allProcesses
                if name of currentProcess is not "WinDock" and name of currentProcess is not "Finder" and name of currentProcess is not "System Events" then
                    try
                        set visible of currentProcess to false
                    end try
                end if
            end repeat
        end tell
        """)
    }
    
    private func executeAppleScript(_ script: String) {
        guard let appleScript = NSAppleScript(source: script) else { return }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error = error {
            AppLogger.shared.error("AppleScript error: \(error)")
        }
    }
}

#Preview {
    DockContextMenuView(appManager: AppManager())
}
