import SwiftUI
import AppKit

struct TaskViewButton: View {
    @State private var isHovered = false
    
    var body: some View {
        Button(action: openMissionControl) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
                    .frame(width: 48, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isHovered ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                            .animation(.easeInOut(duration: 0.15), value: isHovered)
                    )
                
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
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
