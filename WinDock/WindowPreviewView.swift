import SwiftUI
import AppKit

struct WindowPreviewView: View {
    let app: DockApp
    let appManager: AppManager
    @State private var windowPreviews: [WindowPreview] = []
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 0) {
            // App title
            HStack {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                }
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if isLoading {
                VStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading previews...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(height: 120)
                .padding()
            } else if windowPreviews.isEmpty {
                VStack {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No windows")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(height: 120)
                .padding()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(windowPreviews, id: \.windowID) { preview in
                            WindowPreviewItem(
                                preview: preview,
                                app: app,
                                appManager: appManager
                            )
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: min(CGFloat(windowPreviews.count) * 96 + 16, 300))
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 4)
        .frame(width: 280)
        .onAppear {
            loadWindowPreviews()
        }
    }
    
    private func loadWindowPreviews() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let previews = generateWindowPreviews()
            
            DispatchQueue.main.async {
                self.windowPreviews = previews
                self.isLoading = false
            }
        }
    }
    
    private func generateWindowPreviews() -> [WindowPreview] {
        var previews: [WindowPreview] = []
        
        // For now, create mock previews based on window count
        // In a production app, you would use ScreenCaptureKit for real window capture
        for window in app.windows {
            if let image = createPlaceholderPreview(for: window, index: 0) {
                let windowTitle = window.title.isEmpty ? app.name : window.title
                let preview = WindowPreview(
                    windowID: window.windowID,
                    title: windowTitle,
                    image: image,
                    bounds: window.bounds,
                    isMinimized: window.isMinimized
                )
                previews.append(preview)
            }
        }
        
        // If no windows found but app is running, create a single preview
        if previews.isEmpty && app.isRunning {
            if let image = createPlaceholderPreview(for: nil, index: 0) {
                let preview = WindowPreview(
                    windowID: 0,
                    title: app.name,
                    image: image,
                    bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
                    isMinimized: false
                )
                previews.append(preview)
            }
        }
        
        return previews
    }
    
    private func createPlaceholderPreview(for window: WindowInfo?, index: Int) -> NSImage? {
        let image = NSImage(size: NSSize(width: 240, height: 135))
        image.lockFocus()
        
        // Background with app-specific color
        let bgColor = NSColor.controlBackgroundColor
        bgColor.set()
        NSRect(origin: .zero, size: image.size).fill()
        
        // Draw app icon
        if let appIcon = app.icon {
            let iconSize = NSSize(width: 40, height: 40)
            let iconRect = NSRect(
                x: (image.size.width - iconSize.width) / 2,
                y: (image.size.height - iconSize.height) / 2 + 10,
                width: iconSize.width,
                height: iconSize.height
            )
            appIcon.draw(in: iconRect)
        }
        
        // Draw window title
        let title = window?.title ?? app.name
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor
        ]
        let attributedTitle = NSAttributedString(string: title, attributes: attributes)
        let titleSize = attributedTitle.size()
        let titleRect = NSRect(
            x: (image.size.width - titleSize.width) / 2,
            y: 20,
            width: titleSize.width,
            height: titleSize.height
        )
        attributedTitle.draw(in: titleRect)
        
        image.unlockFocus()
        return image
    }
}

struct WindowPreview {
    let windowID: CGWindowID
    let title: String
    let image: NSImage
    let bounds: CGRect
    let isMinimized: Bool
}

struct WindowPreviewItem: View {
    let preview: WindowPreview
    let app: DockApp
    let appManager: AppManager
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 4) {
            // Window preview image
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                
                Image(nsImage: preview.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 240, maxHeight: 135)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    )
                
                // Minimized overlay
                if preview.isMinimized {
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .cornerRadius(4)
                    
                    VStack {
                        Image(systemName: "minus.square.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                        Text("Minimized")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                
                // Close button
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { closeWindow() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                                .background(Color.white, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovered ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.2), value: isHovered)
                    }
                    Spacer()
                }
                .padding(4)
            }
            .frame(height: 72)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                focusWindow()
            }
            
            // Window title
            Text(preview.title)
                .font(.system(size: 10))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
        }
        .padding(4)
    }
    
    private func focusWindow() {
        appManager.focusWindow(windowID: preview.windowID, app: app)
    }
    
    private func closeWindow() {
        // Close specific window using AppleScript
        let script = """
        tell application "System Events"
            tell process "\(app.name)"
                try
                    close window "\(preview.title)"
                end try
            end tell
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
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
            isRunning: true,
            isPinned: true,
            windowCount: 3,
            runningApplication: nil
        ),
        appManager: AppManager()
    )
}
