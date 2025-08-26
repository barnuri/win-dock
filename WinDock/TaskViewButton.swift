import SwiftUI
import AppKit

struct TaskViewButton: View {
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: openMissionControl) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.blue.opacity(0.12) : Color.clear)
                    .frame(width: 48, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isHovered ? Color.blue.opacity(0.4) : Color.clear, 
                                lineWidth: 0.5
                            )
                    )
                
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .brightness(isHovered ? 0.1 : 0.0)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.96 : isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeOut(duration: 0.08)) {
                isPressed = pressing
            }
        }, perform: {})
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
