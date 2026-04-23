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
func CGSHWCaptureWindowList(_ cid: CGSConnectionID, _ windowList: inout CGWindowID, _ windowCount: UInt32, _ options: CGSWindowCaptureOptions) -> Unmanaged<CFArray>?

let CGS_CONNECTION = CGSMainConnectionID()

extension CGWindowID {
    func screenshot() -> CGImage? {
        var wid = self
        guard let unmanaged = CGSHWCaptureWindowList(CGS_CONNECTION, &wid, 1, [.ignoreGlobalClipShape, .bestResolution, .fullSize]) else {
            AppLogger.shared.error("CGSHWCaptureWindowList returned nil for window \(self) — window likely closed/moved")
            return nil
        }
        let arr = unmanaged.takeRetainedValue()
        guard let list = arr as? [CGImage], let first = list.first else {
            AppLogger.shared.error("CGSHWCaptureWindowList cast failed for window \(self)")
            return nil
        }
        return first
    }
}

struct WindowPreviewView: View {
    let app: DockApp
    let appManager: AppManager
    @State private var windowPreviews: [WindowPreview] = []
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    // Pre-computed from app.windowCount so the popover size is stable from the moment
    // it opens — prevents NSPopover._setContentView:size:canAnimate: from triggering
    // an animated resize that crashes in NSMoveHelper._doAnimation.
    private var targetWidth: CGFloat {
        let itemWidth: CGFloat = 220
        let spacing: CGFloat = 12
        let padding: CGFloat = 32
        let displayCount = min(max(app.windowCount, 1), 5)
        return CGFloat(displayCount) * itemWidth + CGFloat(max(0, displayCount - 1)) * spacing + padding
    }

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

            // Horizontal preview layout (Windows 11 style).
            // All branches use the same frame dimensions so the popover never resizes.
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("Loading...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(width: targetWidth, height: 210)
            } else if windowPreviews.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No windows open")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(width: targetWidth, height: 210)
            } else {
                let displayedWindows = Array(windowPreviews.prefix(5))
                let spacing: CGFloat = 12
                let shouldShowScroll = windowPreviews.count > 5

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

                        if windowPreviews.count > 5 {
                            MoreWindowsIndicator(remainingCount: windowPreviews.count - 5)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .frame(width: targetWidth, height: 210)
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
        // Capture value-type snapshot — safe to pass across thread boundaries.
        // NSRunningApplication.processIdentifier is safe to read from any thread.
        let appSnapshot = app

        DispatchQueue.global(qos: .userInitiated).async {
            // Phase 1 (background): only C API calls that are thread-safe.
            // No AppKit (NSImage / NSGradient / NSBezierPath / NSFont) here.
            let captured = Self.captureWindowScreenshots(for: appSnapshot)

            // Phase 2 (main thread): all AppKit / NSImage work.
            DispatchQueue.main.async {
                var previews: [WindowPreview] = []

                for item in captured {
                    let image: NSImage
                    if let cgImage = item.cgImage {
                        image = NSImage(cgImage: cgImage, size: CGSize(width: 220, height: 140))
                    } else if let fallback = self.createAppIconPreview() {
                        image = fallback
                    } else {
                        continue
                    }
                    previews.append(WindowPreview(
                        windowID: item.windowID,
                        title: item.title,
                        image: image,
                        bounds: item.bounds,
                        isMinimized: item.isMinimized
                    ))
                }

                if previews.isEmpty && appSnapshot.isRunning {
                    if let image = self.createAppIconPreview() {
                        previews.append(WindowPreview(
                            windowID: 0,
                            title: appSnapshot.name,
                            image: image,
                            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
                            isMinimized: false
                        ))
                    }
                }

                if previews.isEmpty && !appSnapshot.isRunning {
                    if let image = self.createLaunchPreview() {
                        previews.append(WindowPreview(
                            windowID: 0,
                            title: "Launch \(appSnapshot.name)",
                            image: image,
                            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
                            isMinimized: false
                        ))
                    }
                }

                withAnimation(nil) {
                    self.windowPreviews = previews
                    self.isLoading = false
                }
            }
        }
    }

    // Returns raw screenshot data captured on a background thread.
    // Must NOT touch any AppKit types (NSImage, NSColor semantic variants, NSFont, etc.).
    private static func captureWindowScreenshots(for app: DockApp) -> [(windowID: CGWindowID, cgImage: CGImage?, title: String, bounds: CGRect, isMinimized: Bool)] {
        var results: [(windowID: CGWindowID, cgImage: CGImage?, title: String, bounds: CGRect, isMinimized: Bool)] = []

        if !app.windows.isEmpty {
            for (index, window) in app.windows.enumerated() {
                guard window.windowID != 0 else {
                    AppLogger.shared.warning("Skipping screenshot for \(app.name) window[\(index)] — windowID is 0")
                    continue
                }
                let title = !window.title.isEmpty && window.title != app.name ?
                    window.title : "\(app.name) - Window \(index + 1)"
                AppLogger.shared.info("Capturing screenshot for \(app.name) window[\(index)] id=\(window.windowID)")
                results.append((window.windowID, window.windowID.screenshot(), title, window.bounds, window.isMinimized))
            }
            return results
        }

        guard app.isRunning, let runningApp = app.runningApplication else { return results }

        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        for windowInfo in windowList {
            guard results.count < 10,
                  let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  pid == runningApp.processIdentifier,
                  let windowNumber = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat, let y = boundsDict["Y"] as? CGFloat,
                  let width = boundsDict["Width"] as? CGFloat, let height = boundsDict["Height"] as? CGFloat,
                  width >= 100, height >= 50 else { continue }

            let windowTitle = windowInfo[kCGWindowName as String] as? String ?? ""
            let finalTitle = !windowTitle.isEmpty && windowTitle != app.name ?
                windowTitle : "\(app.name) - Window \(results.count + 1)"

            AppLogger.shared.info("Capturing screenshot for \(app.name) cg-window id=\(windowNumber)")
            results.append((windowNumber, windowNumber.screenshot(), finalTitle, CGRect(x: x, y: y, width: width, height: height), false))
        }

        return results
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