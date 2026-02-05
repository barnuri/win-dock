import SwiftUI
import AppKit

typealias CGSConnectionID = UInt32

struct CGSWindowCaptureOptions: OptionSet {
    let rawValue: UInt32
    static let ignoreGlobalClipShape = CGSWindowCaptureOptions(rawValue: 1 << 11)
    static let bestResolution = CGSWindowCaptureOptions(rawValue: 1 << 8)
    static let fullSize = CGSWindowCaptureOptions(rawValue: 1 << 19)
}

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSHWCaptureWindowList")
func CGSHWCaptureWindowList(_ cid: CGSConnectionID, _ windowList: inout CGWindowID, _ windowCount: UInt32, _ options: CGSWindowCaptureOptions) -> Unmanaged<CFArray>

let CGS_CONNECTION = CGSMainConnectionID()

extension CGWindowID {
    func screenshot() -> CGImage? {
        var windowId = self
        let arrayRef = CGSHWCaptureWindowList(CGS_CONNECTION, &windowId, 1, [.ignoreGlobalClipShape, .bestResolution, .fullSize]).takeRetainedValue()
        
        // Safely cast to [CGImage] instead of force unwrap
        guard let list = arrayRef as? [CGImage] else {
            AppLogger.shared.error("Failed to cast window capture result to [CGImage]")
            return nil
        }
        
        return list.first
    }
}

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
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("Loading...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(height: 160)
                .frame(minWidth: 260)
                .padding()
            } else if windowPreviews.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No windows open")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(height: 160)
                .frame(minWidth: 260)
                .padding()
            } else {
                // Horizontal scrolling layout for multiple windows
                let displayedWindows = Array(windowPreviews.prefix(5))
                let itemWidth: CGFloat = 220
                let spacing: CGFloat = 12
                let padding: CGFloat = 32 // 16 padding on each side
                let maxWindowsToShowWithoutScroll = 5
                
                let shouldShowScroll = windowPreviews.count > maxWindowsToShowWithoutScroll
                let windowsToCalculateWidth = min(displayedWindows.count, maxWindowsToShowWithoutScroll)
                let calculatedWidth = CGFloat(windowsToCalculateWidth) * itemWidth + CGFloat(max(0, windowsToCalculateWidth - 1)) * spacing + padding
                
                ScrollView(.horizontal, showsIndicators: shouldShowScroll) {
                    HStack(spacing: spacing) {
                        ForEach(displayedWindows, id: \.windowID) { preview in
                            WindowsPreviewItem(
                                preview: preview,
                                app: app,
                                appManager: appManager,
                                hasMultipleWindows: windowPreviews.count > 1,
                                onWindowClosed: loadWindowPreviews
                            )
                        }
                        
                        // Show "more windows" indicator if there are more than 5 windows
                        if windowPreviews.count > 5 {
                            MoreWindowsIndicator(remainingCount: windowPreviews.count - 5)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .frame(width: calculatedWidth)
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
                    let windowTitle = !window.title.isEmpty && window.title != app.name ? 
                        window.title : "\(app.name) - Window \(index + 1)"
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
        
        // If no windows from app.windows but app is running, try system APIs (like alt-tab-macos)
        if previews.isEmpty && app.isRunning {
            if let runningApp = app.runningApplication {
                let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
                
                for (_, windowInfo) in windowList.enumerated() {
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
                    
                    // Skip very small windows (likely system windows, like alt-tab-macos)
                    if width < 100 || height < 50 {
                        continue
                    }
                    
                    let windowTitle = windowInfo[kCGWindowName as String] as? String ?? ""
                    let finalTitle = !windowTitle.isEmpty && windowTitle != app.name ? 
                        windowTitle : "\(app.name) - Window \(previews.count + 1)"
                    let bounds = CGRect(x: x, y: y, width: width, height: height)
                    
                    let windowInfoStruct = WindowInfo(
                        title: finalTitle,
                        windowID: windowNumber,
                        bounds: bounds,
                        isMinimized: false,
                        isOnScreen: true
                    )
                    
                    let image = createEnhancedPreview(for: windowInfoStruct, index: previews.count)
                    
                    if let image = image {
                        let preview = WindowPreview(
                            windowID: windowNumber,
                            title: finalTitle,
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
            if let image = createAppIconPreview() {
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
        // Try to get actual screenshot first (like alt-tab-macos)
        if let window = window, let screenshot = window.windowID.screenshot() {
            return NSImage(cgImage: screenshot, size: CGSize(width: 220, height: 140))
        }
        
        // Fallback to app icon preview if screenshot fails
        return createAppIconPreview()
    }
    
    private func createAppIconPreview() -> NSImage? {
        let image = NSImage(size: NSSize(width: 220, height: 140))
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
            let iconSize = NSSize(width: 48, height: 48)
            let iconRect = NSRect(
                x: (image.size.width - iconSize.width) / 2,
                y: (image.size.height - iconSize.height) / 2 + 15,
                width: iconSize.width,
                height: iconSize.height
            )
            
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.shadowBlurRadius = 8
            shadow.set()
            
            appIcon.draw(in: iconRect)
        }
        
        // Clear shadow for text
        let noShadow = NSShadow()
        noShadow.shadowColor = NSColor.clear
        noShadow.set()
        
        // App name
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let attributedTitle = NSAttributedString(string: app.name, attributes: titleAttributes)
        let titleSize = attributedTitle.size()
        let maxTitleWidth = image.size.width - 20
        let titleRect = NSRect(
            x: max(10, (image.size.width - min(titleSize.width, maxTitleWidth)) / 2),
            y: 20,
            width: min(titleSize.width, maxTitleWidth),
            height: titleSize.height
        )
        attributedTitle.draw(in: titleRect)
        
        image.unlockFocus()
        return image
    }
    
    private func createLaunchPreview() -> NSImage? {
        let image = NSImage(size: NSSize(width: 220, height: 140))
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

struct MoreWindowsIndicator: View {
    let remainingCount: Int
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                
                VStack(spacing: 8) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text("+\(remainingCount)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Text("more")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 220, height: 140)
            
            Text("More windows")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: 220)
        }
        .padding(4)
    }
}

// MARK: - Middle Click Detection

struct MiddleClickDetector: NSViewRepresentable {
    let onMiddleClick: (Int) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = MiddleClickView()
        view.onMiddleClick = onMiddleClick
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? MiddleClickView {
            view.onMiddleClick = onMiddleClick
        }
    }
}

class MiddleClickView: NSView {
    var onMiddleClick: ((Int) -> Void)?
    
    override func otherMouseDown(with event: NSEvent) {
        super.otherMouseDown(with: event)
        // Button number 3 is typically the middle button
        onMiddleClick?(Int(event.buttonNumber))
    }
    
    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)
        // Also handle right-click as button 2
        if event.modifierFlags.contains(.control) {
            // Control+click is treated as right-click, don't handle as middle
            return
        }
    }
}