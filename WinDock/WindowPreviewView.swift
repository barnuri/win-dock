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
    @State private var loadToken: Int = 0
    @State private var refreshTask: Task<Void, Never>?
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
                let spacing: CGFloat = 12
                // Show ALL windows; the horizontal ScrollView reveals any beyond the fixed width.
                let shouldShowScroll = windowPreviews.count > 5

                ScrollView(.horizontal, showsIndicators: shouldShowScroll) {
                    HStack(spacing: spacing) {
                        ForEach(windowPreviews, id: \.windowID) { preview in
                            WindowsPreviewItem(
                                preview: preview,
                                app: app,
                                appManager: appManager,
                                hasMultipleWindows: windowPreviews.count > 1,
                                onWindowClosed: { loadWindowPreviews(isInitialLoad: false) }
                            )
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
            startPeriodicRefresh()
        }
        .onDisappear {
            loadToken &+= 1
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    /// Keeps the preview live while the popover is open — reflects windows opened/closed/retitled
    /// elsewhere within ~1s without blocking the main thread or resizing the popover.
    private func startPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1100))
                if Task.isCancelled { break }
                loadWindowPreviews(isInitialLoad: false)
            }
        }
    }
    
    private func loadWindowPreviews(isInitialLoad: Bool = true) {
        if isInitialLoad && windowPreviews.isEmpty {
            isLoading = true
        }
        loadToken &+= 1
        let token = loadToken
        let appSnapshot = app

        // Stall recovery: if enumeration/capture hangs (e.g. AX deadlock), clear the spinner so it
        // can't spin forever. Guard on isLoading only (NOT the per-load token — the 1.1s periodic
        // refresh bumps the token within 1.1s, which would otherwise defeat this timer). isLoading
        // is only true during the first load, so clearing it from any settled timer is safe.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            guard self.isLoading else { return }
            self.isLoading = false
        }

        Task { @MainActor in
            // Fetch a fresh window list (off-main via the actor), bypassing the dock's 5s cache,
            // so the preview reflects the app's current windows — including ones opened after the
            // popover appeared.
            let liveWindows = await appManager.liveWindows(for: appSnapshot)
            guard self.loadToken == token else { return }

            // Capture screenshots off the main thread (thread-safe C APIs only — no AppKit).
            let captured = await Task.detached(priority: .userInitiated) {
                WindowPreviewView.captureWindowScreenshots(windows: liveWindows, app: appSnapshot)
            }.value
            guard self.loadToken == token else { return }

            // Build NSImages on the main thread (AppKit).
            var previews: [WindowPreview] = []
            for item in captured {
                let image: NSImage
                if let cgImage = item.cgImage {
                    // Native pixel size preserves aspect ratio under .aspectRatio in WindowsPreviewItem.
                    image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                } else if item.isMinimized, let placeholder = self.createAppIconPreview() {
                    // Minimized windows have no live surface — show a placeholder; the item draws
                    // a "Minimized" overlay on top so the window is still represented.
                    image = placeholder
                } else {
                    // Screenshot failed for a non-minimized window — closed or surface gone.
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

            if previews.isEmpty && appSnapshot.isRunning, let image = self.createAppIconPreview() {
                previews.append(WindowPreview(
                    windowID: 0,
                    title: appSnapshot.name,
                    image: image,
                    bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
                    isMinimized: false
                ))
            }
            if previews.isEmpty && !appSnapshot.isRunning, let image = self.createLaunchPreview() {
                previews.append(WindowPreview(
                    windowID: 0,
                    title: "Launch \(appSnapshot.name)",
                    image: image,
                    bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
                    isMinimized: false
                ))
            }

            withAnimation(nil) {
                self.windowPreviews = previews
                self.isLoading = false
            }
        }
    }

    // Preview items render at 220pt wide; 440px covers Retina @2x. Downsampling here keeps
    // full-window captures (which can be 5K+ wide) from holding megabytes per thumbnail.
    static let maxPreviewPixelWidth = 440

    // CoreGraphics-only, safe on background threads. Internal for unit testing.
    static func downsampled(_ image: CGImage) -> CGImage {
        guard image.width > maxPreviewPixelWidth else { return image }
        let scale = CGFloat(maxPreviewPixelWidth) / CGFloat(image.width)
        let height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(
            data: nil,
            width: maxPreviewPixelWidth,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: maxPreviewPixelWidth, height: height))
        return context.makeImage() ?? image
    }

    // Returns raw screenshot data captured on a background thread.
    // Must NOT touch any AppKit types (NSImage, NSColor semantic variants, NSFont, etc.).
    private static func captureWindowScreenshots(windows: [WindowInfo], app: DockApp) -> [(windowID: CGWindowID, cgImage: CGImage?, title: String, bounds: CGRect, isMinimized: Bool)] {
        var results: [(windowID: CGWindowID, cgImage: CGImage?, title: String, bounds: CGRect, isMinimized: Bool)] = []

        if !windows.isEmpty {
            // Build a live set of window IDs to filter out windows that have been closed
            // since the last dock update. CGSHWCaptureWindowList can return a stale
            // surface for a recently-closed ID, so membership check is the reliable gate.
            let liveWindowIDs: Set<CGWindowID>
            if let rawList = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                liveWindowIDs = Set(rawList.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
            } else {
                liveWindowIDs = []
            }

            for (index, window) in windows.enumerated() {
                guard window.windowID != 0 else {
                    AppLogger.shared.warning("Skipping screenshot for \(app.name) window[\(index)] — windowID is 0")
                    continue
                }
                // Skip windows absent from the live list (process exited or window closed).
                // Minimized windows legitimately have no on-screen surface, so trust the AX
                // enumeration for those. Allow all through if liveWindowIDs is empty (API failure).
                if !liveWindowIDs.isEmpty && !liveWindowIDs.contains(window.windowID) && !window.isMinimized {
                    AppLogger.shared.info("Skipping dead window \(window.windowID) for \(app.name) — not in live list")
                    continue
                }
                let title = !window.title.isEmpty && window.title != app.name ?
                    window.title : "\(app.name) - Window \(index + 1)"
                AppLogger.shared.info("Capturing screenshot for \(app.name) window[\(index)] id=\(window.windowID)")
                results.append((window.windowID, window.windowID.screenshot().map(Self.downsampled), title, window.bounds, window.isMinimized))
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
            results.append((windowNumber, windowNumber.screenshot().map(Self.downsampled), finalTitle, CGRect(x: x, y: y, width: width, height: height), false))
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
        // macOS button numbers: 0=left, 1=right, 2=middle. The handler filters for middle.
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