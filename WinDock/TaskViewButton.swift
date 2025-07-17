import SwiftUI
import AppKit

struct TaskViewButton: View {
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: openMissionControl) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundFill)
                    .frame(width: 48, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isHovered ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
        .help("Task View (Mission Control)")
    }
    
    private var backgroundFill: some ShapeStyle {
        if isPressed {
            return AnyShapeStyle(Color.accentColor.opacity(0.2))
        }
        if isHovered {
            return AnyShapeStyle(Color.accentColor.opacity(0.15))
        }
        return AnyShapeStyle(Color.clear)
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
