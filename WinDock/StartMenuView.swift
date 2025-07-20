import SwiftUI
import AppKit

struct StartMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var appManager = AppManager()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "apple.logo")
                    .font(.title2)
                    .foregroundColor(.primary)
                Text("Start")
                    .font(.headline)
                    .fontWeight(.medium)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Quick Actions
            VStack(alignment: .leading, spacing: 4) {
                Text("Quick Actions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                
                VStack(spacing: 2) {
                    StartMenuButton(
                        title: "Close All Windows",
                        icon: "xmark.square.fill",
                        action: closeAllWindows
                    )
                    
                    StartMenuButton(
                        title: "Hide All Windows",
                        icon: "eye.slash.fill",
                        action: hideAllWindows
                    )
                    
                    StartMenuButton(
                        title: "Show Desktop",
                        icon: "rectangle.dashed",
                        action: showDesktop
                    )
                    
                    Divider()
                        .padding(.horizontal, 16)
                    
                    StartMenuButton(
                        title: "Activity Monitor",
                        icon: "chart.bar.fill",
                        action: openActivityMonitor
                    )
                    
                    StartMenuButton(
                        title: "Terminal",
                        icon: "terminal.fill",
                        action: openTerminal
                    )
                    
                    StartMenuButton(
                        title: "System Preferences",
                        icon: "gearshape.fill",
                        action: openSystemPreferences
                    )
                    
                    StartMenuButton(
                        title: "Finder",
                        icon: "folder.fill",
                        action: openFinder
                    )
                    
                    Divider()
                        .padding(.horizontal, 16)
                    
                    StartMenuButton(
                        title: "Mission Control",
                        icon: "square.grid.3x3",
                        action: openMissionControl
                    )
                    
                    StartMenuButton(
                        title: "Launchpad",
                        icon: "grid.circle.fill",
                        action: openLaunchpad
                    )
                    
                    StartMenuButton(
                        title: "Spotlight Search",
                        icon: "magnifyingglass",
                        action: openSpotlight
                    )
                }
            }
            .padding(.bottom, 8)
            
            Divider()
            
            // App Options
            VStack(alignment: .leading, spacing: 4) {
                Text("WinDock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                
                VStack(spacing: 2) {
                    StartMenuButton(
                        title: "Settings",
                        icon: "gearshape.fill",
                        action: openWinDockSettings
                    )
                    
                    StartMenuButton(
                        title: "Quit WinDock",
                        icon: "xmark.circle.fill",
                        action: quitWinDock
                    )
                }
            }
            .padding(.bottom, 8)
            
            Divider()
            
            // Power Options
            VStack(alignment: .leading, spacing: 4) {
                Text("Power")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                
                VStack(spacing: 2) {
                    StartMenuButton(
                        title: "Sleep",
                        icon: "moon.fill",
                        action: sleep
                    )
                    
                    StartMenuButton(
                        title: "Restart",
                        icon: "arrow.clockwise",
                        action: restart
                    )
                    
                    StartMenuButton(
                        title: "Shut Down",
                        icon: "power",
                        action: shutdown
                    )
                    
                    StartMenuButton(
                        title: "Lock Screen",
                        icon: "lock.fill",
                        action: lockScreen
                    )
                    
                    StartMenuButton(
                        title: "Log Out",
                        icon: "person.crop.circle.badge.minus",
                        action: logOut
                    )
                }
            }
            .padding(.bottom, 16)
        }
        .frame(width: 280)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Actions
    
    private func closeAllWindows() {
        let script = """
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
        """
        executeAppleScript(script)
        dismiss()
    }
    
    private func hideAllWindows() {
        let script = """
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
        """
        executeAppleScript(script)
        dismiss()
    }
    
    private func showDesktop() {
        let script = """
        tell application "System Events"
            key code 103 using {command down}
        end tell
        """
        executeAppleScript(script)
        dismiss()
    }
    
    private func openActivityMonitor() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        dismiss()
    }
    
    private func openTerminal() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        dismiss()
    }
    
    private func openSystemPreferences() {
        if #available(macOS 13.0, *) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!)
        } else {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
        dismiss()
    }
    
    private func openFinder() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        dismiss()
    }
    
    private func openMissionControl() {
        let script = """
        tell application "System Events"
            key code 131 using {control down}
        end tell
        """
        executeAppleScript(script)
        dismiss()
    }
    
    private func openLaunchpad() {
        let script = """
        tell application "System Events"
            key code 131
        end tell
        """
        executeAppleScript(script)
        dismiss()
    }
    
    private func openSpotlight() {
        let script = """
        tell application "System Events"
            key code 49 using {command down}
        end tell
        """
        executeAppleScript(script)
        dismiss()
    }
    
    private func openWinDockSettings() {
        AppLogger.shared.info("Opening WinDock settings from StartMenuView")
        SettingsHelper.shared.requestOpenSettings()
        dismiss()
    }
    
    private func quitWinDock() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.terminate(nil)
        }
    }
    
    private func sleep() {
        let script = """
        tell application "System Events"
            sleep
        end tell
        """
        executeAppleScript(script)
        dismiss()
    }
    
    private func restart() {
        let script = """
        tell application "System Events"
            restart
        end tell
        """
        executeAppleScript(script)
        dismiss()
    }
    
    private func shutdown() {
        let script = """
        tell application "System Events"
            shut down
        end tell
        """
        executeAppleScript(script)
        dismiss()
    }
    
    private func lockScreen() {
        let script = """
        tell application "System Events"
            keystroke "q" using {control down, command down}
        end tell
        """
        executeAppleScript(script)
        dismiss()
    }
    
    private func logOut() {
        let script = """
        tell application "System Events"
            log out
        end tell
        """
        executeAppleScript(script)
        dismiss()
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

struct StartMenuButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                    .frame(width: 20, alignment: .center)
                
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    StartMenuView()
        .preferredColorScheme(.light)
}
