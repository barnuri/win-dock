import SwiftUI
import AppKit

struct WindowPreviewView: View {
    let app: DockApp
    let appManager: AppManager
    @State private var windowPreviews: [WindowPreview] = []
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // App header with title and close button
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
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(Color.secondary.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Horizontal preview layout (Windows 11 style)
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading windows...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(height: 120)
                .padding()
            } else if windowPreviews.isEmpty {
                HStack {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                    Text("No windows available")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(height: 120)
                .padding()
            } else {
                // Horizontal scrolling layout for multiple windows
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(windowPreviews, id: \.windowID) { preview in
                            WindowsPreviewItem(
                                preview: preview,
                                app: app,
                                appManager: appManager,
                                hasMultipleWindows: windowPreviews.count > 1
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .frame(maxWidth: min(CGFloat(windowPreviews.count) * 200 + CGFloat(windowPreviews.count - 1) * 12 + 32, 800))
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 8)
        .onAppear {
            loadWindowPreviews()
        }
    }
    
    private func loadWindowPreviews() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let previews = self.generateWindowPreviews()
            
            DispatchQueue.main.async {
                self.windowPreviews = previews
                self.isLoading = false
            }
        }
    }
    
    private func generateWindowPreviews() -> [WindowPreview] {
        var previews: [WindowPreview] = []
        
        // First, try to get windows from the app's windows array
        if !app.windows.isEmpty {
            for (index, window) in app.windows.enumerated() {
                let image = createEnhancedPreview(for: window, index: index)
                
                if let image = image {
                    let windowTitle = window.title.isEmpty ? "Window \(index + 1)" : window.title
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
        }
        
        // If no windows from app.windows but app is running, try to get windows via system APIs
        if previews.isEmpty && app.isRunning {
            if let runningApp = app.runningApplication {
                // Get windows using NSRunningApplication
                let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
                
                for (index, windowInfo) in windowList.enumerated() {
                    guard let windowPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                          windowPID == runningApp.processIdentifier,
                          let windowNumber = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                          let windowBounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
                          let x = windowBounds["X"] as? CGFloat,
                          let y = windowBounds["Y"] as? CGFloat,
                          let width = windowBounds["Width"] as? CGFloat,
                          let height = windowBounds["Height"] as? CGFloat else {
                        continue
                    }
                    
                    // Skip very small windows (likely system windows)
                    if width < 100 || height < 50 {
                        continue
                    }
                    
                    let windowTitle = windowInfo[kCGWindowName as String] as? String ?? "Window \(index + 1)"
                    let bounds = CGRect(x: x, y: y, width: width, height: height)
                    
                    let windowInfoStruct = WindowInfo(
                        title: windowTitle,
                        windowID: windowNumber,
                        bounds: bounds,
                        isMinimized: false,
                        isOnScreen: true
                    )
                    
                    let image = createEnhancedPreview(for: windowInfoStruct, index: previews.count)
                    
                    if let image = image {
                        let preview = WindowPreview(
                            windowID: windowNumber,
                            title: windowTitle,
                            image: image,
                            bounds: bounds,
                            isMinimized: false
                        )
                        previews.append(preview)
                    }
                    
                    // Limit to 10 windows to avoid performance issues
                    if previews.count >= 10 {
                        break
                    }
                }
            }
        }
        
        // If still no window previews but app is running, create a single app preview
        if previews.isEmpty && app.isRunning {
            if let image = createEnhancedPreview(for: nil, index: 0) {
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
        
        // If app is not running, show a launch preview
        if previews.isEmpty && !app.isRunning {
            if let image = createLaunchPreview() {
                let preview = WindowPreview(
                    windowID: 0,
                    title: "Launch \(app.name)",
                    image: image,
                    bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
                    isMinimized: false
                )
                previews.append(preview)
            }
        }
        
        return previews
    }
    
    private func createEnhancedPreview(for window: WindowInfo?, index: Int) -> NSImage? {
        let image = NSImage(size: NSSize(width: 180, height: 120))
        image.lockFocus()
        
        // Windows 11-style background with subtle gradient
        let bgGradient = NSGradient(colors: [
            NSColor.controlBackgroundColor,
            NSColor.controlBackgroundColor.blended(withFraction: 0.05, of: NSColor.systemBlue) ?? NSColor.controlBackgroundColor
        ])
        bgGradient?.draw(in: NSRect(origin: .zero, size: image.size), angle: 45)
        
        // Modern rounded border
        let borderPath = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: image.size.width - 2, height: image.size.height - 2), xRadius: 8, yRadius: 8)
        NSColor.separatorColor.setStroke()
        borderPath.lineWidth = 1
        borderPath.stroke()
        
        // Draw app icon with modern shadow
        if let appIcon = app.icon {
            let iconSize = NSSize(width: 32, height: 32)
            let iconRect = NSRect(
                x: (image.size.width - iconSize.width) / 2,
                y: (image.size.height - iconSize.height) / 2 + 12,
                width: iconSize.width,
                height: iconSize.height
            )
            
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.shadowBlurRadius = 6
            shadow.set()
            
            appIcon.draw(in: iconRect)
        }
        
        // Clear shadow for text
        let noShadow = NSShadow()
        noShadow.shadowColor = NSColor.clear
        noShadow.set()
        
        // Window title
        let title = window?.title ?? app.name
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let attributedTitle = NSAttributedString(string: title, attributes: titleAttributes)
        let titleSize = attributedTitle.size()
        let titleRect = NSRect(
            x: (image.size.width - titleSize.width) / 2,
            y: 20,
            width: titleSize.width,
            height: titleSize.height
        )
        attributedTitle.draw(in: titleRect)
        
        // Window status
        if let window = window {
            let status = window.isMinimized ? "Minimized" : "Active"
            let statusAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: window.isMinimized ? NSColor.systemOrange : NSColor.systemGreen
            ]
            let attributedStatus = NSAttributedString(string: status, attributes: statusAttributes)
            let statusSize = attributedStatus.size()
            let statusRect = NSRect(
                x: (image.size.width - statusSize.width) / 2,
                y: 8,
                width: statusSize.width,
                height: statusSize.height
            )
            attributedStatus.draw(in: statusRect)
        }
        
        image.unlockFocus()
        return image
    }
    
    private func createLaunchPreview() -> NSImage? {
        let image = NSImage(size: NSSize(width: 180, height: 120))
        image.lockFocus()
        
        // Launch-themed background
        let bgGradient = NSGradient(colors: [
            NSColor.systemBlue.withAlphaComponent(0.1),
            NSColor.systemBlue.withAlphaComponent(0.05)
        ])
        bgGradient?.draw(in: NSRect(origin: .zero, size: image.size), angle: 45)
        
        // Border
        let borderPath = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: image.size.width - 2, height: image.size.height - 2), xRadius: 8, yRadius: 8)
        NSColor.systemBlue.withAlphaComponent(0.3).setStroke()
        borderPath.lineWidth = 1
        borderPath.stroke()
        
        // App icon
        if let appIcon = app.icon {
            let iconSize = NSSize(width: 40, height: 40)
            let iconRect = NSRect(
                x: (image.size.width - iconSize.width) / 2,
                y: (image.size.height - iconSize.height) / 2 + 8,
                width: iconSize.width,
                height: iconSize.height
            )
            appIcon.draw(in: iconRect)
        }
        
        // Launch text
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let attributedTitle = NSAttributedString(string: app.name, attributes: titleAttributes)
        let titleSize = attributedTitle.size()
        let titleRect = NSRect(
            x: (image.size.width - titleSize.width) / 2,
            y: 20,
            width: titleSize.width,
            height: titleSize.height
        )
        attributedTitle.draw(in: titleRect)
        
        let infoAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.systemBlue
        ]
        let attributedInfo = NSAttributedString(string: "Click to launch", attributes: infoAttributes)
        let infoSize = attributedInfo.size()
        let infoRect = NSRect(
            x: (image.size.width - infoSize.width) / 2,
            y: 8,
            width: infoSize.width,
            height: infoSize.height
        )
        attributedInfo.draw(in: infoRect)
        
        image.unlockFocus()
        return image
    }
}

struct WindowsPreviewItem: View {
    let preview: WindowPreview
    let app: DockApp
    let appManager: AppManager
    let hasMultipleWindows: Bool
    @State private var isHovered = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
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
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 180, height: 120)
                    .cornerRadius(6)
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
                
                // Close button with Windows 11 style
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { closeWindow() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(
                                    Circle()
                                        .fill(Color.red.opacity(0.8))
                                )
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovered ? 1.0 : 0.0)
                    }
                    Spacer()
                }
                .padding(6)
            }
            .frame(width: 180, height: 120)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.blue.opacity(0.1) : Color.clear)
                    .animation(.easeOut(duration: 0.15), value: isHovered)
            )
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                focusWindow()
                dismiss()
            }
            
            // Window title
            Text(preview.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 180)
        }
        .padding(4)
    }
    
    private func focusWindow() {
        if preview.windowID > 0 {
            appManager.focusWindow(windowID: preview.windowID, app: app)
            return
        }
        appManager.activateApp(app)
    }
    
    private func closeWindow() {
        // Get the proper process name for System Events
        let processName = app.runningApplication?.localizedName ?? app.name
        
        let script = """
        tell application "System Events"
            try
                tell process "\(processName)"
                    try
                        close window "\(preview.title)"
                    end try
                end tell
            on error
                -- Fallback: try with the display name
                try
                    tell process "\(app.name)"
                        try
                            close window "\(preview.title)"
                        end try
                    end tell
                end try
            end try
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                AppLogger.shared.warning("Close window AppleScript error: \(error)")
            }
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
            runningApplication: nil,
            windows: [],
            notificationCount: 0,
            hasNotifications: false
        ),
        appManager: AppManager()
    )
}


struct WindowPreview {
    let windowID: CGWindowID
    let title: String
    let image: NSImage
    let bounds: CGRect
    let isMinimized: Bool
}