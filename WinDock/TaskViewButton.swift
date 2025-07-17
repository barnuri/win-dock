import SwiftUI
import AppKit

struct TaskViewButton: View {
    
    var body: some View {
        Button(action: openMissionControl) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.clear)
                    .frame(width: 48, height: 38)
                
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
        .help("Task View (Mission Control)")
    }
    
    private func openMissionControl() {
        let script = """
        tell application "System Events"
            key code 131 using {control down}
        end tell
        """
        executeAppleScript(script)
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
    TaskViewButton()
        .preferredColorScheme(.light)
}
