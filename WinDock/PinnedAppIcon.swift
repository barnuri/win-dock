import SwiftUI
import AppKit

struct PinnedAppIcon: View {
    let appName: String
    let dismiss: DismissAction
    @State private var showMenu = false

    var body: some View {
        VStack {
            Image(systemName: "app.fill")
                .font(.system(size: 32))
                .foregroundColor(.blue)
            Text(appName)
                .font(.caption)
                .lineLimit(1)
        }
        .frame(width: 80, height: 80)
        .contentShape(Rectangle())
        .onTapGesture {
            let script = "tell application \"System Events\" to key code 160 using {control down, option down, command down}"
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
            dismiss()
        }
        .onTapGesture(count: 2) {
            let script = "tell application \"System Events\" to key code 160 using {control down, option down, command down}"
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
            dismiss()
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            showMenu = true
        }
        .contextMenu(menuItems: {
            Button("Close All Windows") {
                NSWorkspace.shared.runningApplications.forEach { $0.hide() }
            }
            Button("Minimize All Windows") {
                let script = "tell application \"System Events\" to keystroke 'm' using {command down, option down}"
                if let appleScript = NSAppleScript(source: script) {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                }
            }
            Button("Open Monitor") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Utilities/Activity Monitor.app"))
            }
            Button("Lock Screen") {
                lockScreen()
            }
            Button("Sleep") {
                let script = "tell application \"System Events\" to sleep"
                if let appleScript = NSAppleScript(source: script) {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                }
            }
            Button("Poweroff") {
                let script = "tell application \"System Events\" to shut down"
                if let appleScript = NSAppleScript(source: script) {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                }
            }
        })
    }
}
