import SwiftUI
import AppKit

struct WindowsPreviewItem: View {
    let preview: WindowPreview
    let app: DockApp
    let appManager: AppManager
    let hasMultipleWindows: Bool
    let onWindowClosed: () -> Void
    @State private var isHovered = false
    @State private var middleClickDetected = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Button(action: {
            onTap()
            dismiss()
        }) {
            VStack(spacing: 8) {
                // Preview image with Windows 11 styling
                ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                
                Image(nsImage: preview.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 220, height: 140)
                    .cornerRadius(6)
                    .clipped()
                    .brightness(hasMultipleWindows ? 0.1 : 0.0) // Double-brighten for multiple windows
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    )
                
                // Minimized overlay
                if preview.isMinimized {
                    Rectangle()
                        .fill(Color.black.opacity(0.4))
                        .cornerRadius(6)
                    
                    VStack(spacing: 4) {
                        Image(systemName: "minus.square.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                        Text("Minimized")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                
                // Close button with Windows 11 style - always visible on hover
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { closeWindow() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(
                                    Circle()
                                        .fill(Color.red)
                                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovered ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                    }
                    Spacer()
                }
                .padding(6)
            }
            .frame(width: 220, height: 140)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.blue.opacity(0.1) : Color.clear)
                    .animation(.easeOut(duration: 0.15), value: isHovered)
            )
            .background(
                // Add middle-click detection
                MiddleClickDetector { buttonNumber in
                    if buttonNumber == 3 { // Middle button
                        closeWindow()
                        dismiss()
                    }
                }
            )
            .onHover { hovering in
                isHovered = hovering
            }
            
            // Window title
            Text(preview.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: 220)
                .multilineTextAlignment(.center)
        }
        }
        .buttonStyle(.plain)
        .contextMenu {
                Button("Close Window") {
                    closeWindow()
                    dismiss()
                }
                Divider()
                Button("Activate Window") {
                    onTap()
                    dismiss()
                }
            }
        .padding(4)
    }
    
    private func onTap() {
        if preview.windowID > 0 {
            appManager.focusWindow(windowID: preview.windowID, app: app)
            return
        }
        appManager.activateApp(app)
    }
    
    private func closeWindow() {
        let success = appManager.closeWindow(
            windowID: preview.windowID,
            windowTitle: preview.title,
            app: app
        )
        
        if success {
            onWindowClosed()
        }
    }
}

#Preview {
    WindowPreviewView(
        app: DockApp(
            bundleIdentifier: "com.apple.Safari",
            name: "Safari",
            icon: NSWorkspace.shared.icon(forFile: "/Applications/Safari.app"),
            url: nil,
            isPinned: true,
            runningApplication: nil,
            windows: [],
            notificationCount: 0,
            hasNotifications: false
        ),
        appManager: AppManager()
    )
}