import AppKit
import CoreGraphics
import SwiftUI

// This class manages the resizing of windows to prevent overlap with the dock area.
// It observes window events and adjusts positions as necessary.
// It also handles dock area updates based on user settings and screen parameters.
// The manager runs in the background and can be started/stopped based on user preferences.
// It prefers to only move windows that are overlapping the dock area.
// Resizing is a secondary action to ensure the window remains on screen after being moved.
// do it only for the running, active and visible windows
// create relevant logs of start, stop, and adjustments
// This class is a singleton to ensure only one instance manages window resizing across the app.

class WindowsResizeManager: ObservableObject {

    // MARK: - Properties

    static let shared = WindowsResizeManager()

    @Published private(set) var isRunning = false

    private var dockAreas: [NSScreen: CGRect] = [:]
    private var dockPosition: DockPosition = .bottom
    private var monitoringTimer: Timer?
    /// Frames we tried to move a window away from, with the attempt count. After
    /// `maxAdjustmentAttempts` the app is assumed to snap it back, so we stop retrying.
    private var rejectedAdjustments: [CGWindowID: (frame: CGRect, attempts: Int)] = [:]
    private static let maxAdjustmentAttempts = 3
    private static let minimumWindowSize = CGSize(width: 100, height: 50)
    
    // References to other managers for state checking
    private let fullscreenManager = FullscreenDetectionManager.shared

    // MARK: - Lifecycle & Running Control

    private init() {
        setupNotifications()
        updateDockAreaFromSettings()
    }

    deinit {
        stop()
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        guard !isRunning else { return }

        if !checkAccessibilityPermissions() {
            requestAccessibilityPermissions()
            return
        }

        isRunning = true
        updateDockAreaFromSettings()
        startPeriodicMonitoring()
        AppLogger.shared.info("WindowsResizeManager started successfully.")
    }

    func stop() {
        guard isRunning else { return }

        isRunning = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        AppLogger.shared.info("WindowsResizeManager stopped.")
    }

    // MARK: - Notification Handling

    private func setupNotifications() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(
            self,
            selector: #selector(dockSettingsChanged),
            name: NSNotification.Name("WinDockPositionChanged"),
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(userDefaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func userDefaultsChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshDockAreasIfChanged()
        }
    }

    private func refreshDockAreasIfChanged() {
        let positionRaw = UserDefaults.standard.string(forKey: "dockPosition") ?? "bottom"
        let newAreas = Dictionary(uniqueKeysWithValues: NSScreen.screens.map {
            ($0, dockFrame(for: DockPosition(rawValue: positionRaw) ?? .bottom, screen: $0))
        })
        guard newAreas != dockAreas else { return }
        updateDockAreaFromSettings()
    }

    @objc private func dockSettingsChanged() {
        let enableWindowsResize = UserDefaults.standard.bool(forKey: "enableWindowsResize")
        if enableWindowsResize && !isRunning {
            start()
        } else if !enableWindowsResize && isRunning {
            stop()
        }
        
        updateDockAreaFromSettings()
        if isRunning {
            resizeAndMoveWindowsIfNeeded()
        }
    }

    @objc private func screenParametersChanged() {
        updateDockAreaFromSettings()
        if isRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.resizeAndMoveWindowsIfNeeded()
            }
        }
    }

    // MARK: - Dock Area Management

    private func updateDockAreaFromSettings() {
        let dockPositionStr = UserDefaults.standard.string(forKey: "dockPosition") ?? "bottom"
        dockPosition = DockPosition(rawValue: dockPositionStr) ?? .bottom

        dockAreas.removeAll()
        rejectedAdjustments.removeAll()
        for (index, screen) in NSScreen.screens.enumerated() {
            let dockArea = dockFrame(for: dockPosition, screen: screen)
            dockAreas[screen] = dockArea
            AppLogger.shared.info("Screen \(index): \(screen.frame), Dock area: \(dockArea)")
        }
        AppLogger.shared.info("Updated dock areas for position: \(dockPosition.rawValue) across \(NSScreen.screens.count) screens")
    }

    // MARK: - Accessibility Permissions

    private func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Window Monitoring & Adjustment

    private func startPeriodicMonitoring() {
        monitoringTimer?.invalidate()
        // Settings/screen-change notifications drive prompt adjustments; this is a low-frequency
        // safety sweep. The scan is skipped entirely when resizing is disabled.
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.resizeAndMoveWindowsIfNeeded()
        }
    }
    
    /// Checks if window resizing should be disabled based on dock hiding or fullscreen state
    private func shouldDisableResizing() -> Bool {
        // Check if WinDock auto-hide is enabled and dock is currently hidden
        let autoHide = UserDefaults.standard.bool(forKey: "autoHide")
        
        // Check if there's a fullscreen window
        let hasFullscreenWindow = fullscreenManager.hasFullscreenWindow
               
        if autoHide {
            AppLogger.shared.debug("Window resizing disabled: WinDock auto-hide is enabled")
            return true
        }
        
        if hasFullscreenWindow {
            AppLogger.shared.debug("Window resizing disabled: Fullscreen window detected")
            return true
        }
        
        return false
    }

    func resizeAndMoveWindowsIfNeeded() {
        guard isRunning, !dockAreas.isEmpty else {
            AppLogger.shared.warning("WindowsResizeManager is not running or dock areas are empty.")
            return
        }
        if shouldDisableResizing() { return }

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            AppLogger.shared.error("Failed to retrieve window list.")
            return
        }

        let filteredWindows = windowList.compactMap { windowInfo -> (windowInfo: [String: Any], pid: pid_t, windowFrame: CGRect)? in
            guard
                let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                let windowFrame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                windowInfo[kCGWindowIsOnscreen as String] as? Bool == true,
                windowInfo[kCGWindowLayer as String] as? Int == 0,
                windowFrame.width > Self.minimumWindowSize.width,
                windowFrame.height > Self.minimumWindowSize.height
            else { return nil }
            return (windowInfo, pid, windowFrame)
        }
        guard !filteredWindows.isEmpty else { return }
        pruneRejectedAdjustments(liveWindowFrames: windowFrames(in: windowList))

        // dockAreas come from dockFrame() which uses NSScreen.visibleFrame — AppKit coords
        // (origin at bottom-left of main screen, Y increases upward).
        // CGWindowListCopyWindowInfo returns bounds in CG/Quartz coords
        // (origin at top-left of main screen, Y increases downward).
        // Convert all dock areas to CG coords once so intersection math is correct.
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let dockAreasCG: [NSScreen: CGRect] = dockAreas.mapValues { appkitRect in
            CGRect(
                x: appkitRect.minX,
                y: mainScreenHeight - appkitRect.maxY,
                width: appkitRect.width,
                height: appkitRect.height
            )
        }

        for filteredWindow in filteredWindows {
            let windowFrame = filteredWindow.windowFrame  // CG coords
            let windowID = filteredWindow.windowInfo[kCGWindowNumber as String] as? CGWindowID ?? 0
            if let rejected = rejectedAdjustments[windowID], rejected.frame == windowFrame,
               rejected.attempts >= Self.maxAdjustmentAttempts {
                continue
            }

            for (screen, dockAreaCG) in dockAreasCG {
                let screenFrameCG = CGRect(
                    x: screen.frame.minX,
                    y: mainScreenHeight - screen.frame.maxY,
                    width: screen.frame.width,
                    height: screen.frame.height
                )

                guard screenFrameCG.intersects(windowFrame) && windowFrame.intersects(dockAreaCG),
                      let app = Self.adjustableApp(pid: filteredWindow.pid) else {
                    continue
                }

                var newFrame = windowFrame
                let margin: CGFloat = 4
                var resized = false

                // Boundaries in CG coords derived from visibleFrame (which excludes menu bar
                // and macOS Dock). Windows cannot be placed above the menu bar — macOS silently
                // snaps them back — so availableHeight must account for it.
                let menuBarCGBottom = mainScreenHeight - screen.visibleFrame.maxY
                let bottomBoundaryCG = mainScreenHeight - screen.visibleFrame.minY

                if dockPosition == .bottom || dockPosition == .top {
                    let availableHeight: CGFloat = dockPosition == .bottom
                        ? dockAreaCG.minY - menuBarCGBottom - margin
                        : bottomBoundaryCG - dockAreaCG.maxY - margin
                    if newFrame.height > availableHeight {
                        newFrame.size.height = max(1, availableHeight)
                        resized = true
                    }
                } else {
                    let availableWidth = screenFrameCG.width - dockAreaCG.width - margin
                    if newFrame.width > availableWidth {
                        newFrame.size.width = max(1, availableWidth)
                        resized = true
                    }
                }

                // Position window to clear the dock. For .bottom, clamp to menu bar so macOS
                // doesn't reject the position and snap the window back (causing an infinite loop).
                switch dockPosition {
                case .bottom:
                    newFrame.origin.y = max(menuBarCGBottom, dockAreaCG.minY - newFrame.height)
                case .top:
                    newFrame.origin.y = dockAreaCG.maxY + margin
                case .left:
                    newFrame.origin.x = dockAreaCG.maxX + margin
                case .right:
                    newFrame.origin.x = dockAreaCG.minX - newFrame.width
                }

                guard newFrame != windowFrame else { continue }
                let previousAttempts = rejectedAdjustments[windowID].flatMap { $0.frame == windowFrame ? $0.attempts : nil } ?? 0
                rejectedAdjustments[windowID] = (windowFrame, previousAttempts + 1)

                AppLogger.shared.info("Adjusting window for \(app.localizedName ?? "Unknown") from \(windowFrame) to \(newFrame). Resized: \(resized)")

                guard let axWindow = findAXWindow(for: app.processIdentifier, matchingCGFrame: windowFrame) else {
                    AppLogger.shared.error("Could not find matching AX window for \(app.localizedName ?? "Unknown")")
                    continue
                }

                if resized {
                    if let sizeValue = AXValue.from(value: newFrame.size, type: .cgSize),
                       AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue) == .success {
                        AppLogger.shared.info("Successfully resized window for \(app.localizedName ?? "Unknown")")
                    } else {
                        AppLogger.shared.error("Failed to resize window for \(app.localizedName ?? "Unknown")")
                    }
                }
                if let positionValue = AXValue.from(value: newFrame.origin, type: .cgPoint),
                   AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue) == .success {
                    AppLogger.shared.info("Successfully moved window for \(app.localizedName ?? "Unknown")")
                } else {
                    AppLogger.shared.error("Failed to move window for \(app.localizedName ?? "Unknown")")
                }
            }
        }
    }

    /// NSRunningApplication lookup is an IPC round-trip, so it runs only for windows touching a dock area.
    private static func adjustableApp(pid: pid_t) -> NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              !app.isTerminated,
              !app.isHidden else { return nil }
        return app
    }

    private func windowFrames(in windowList: [[String: Any]]) -> [CGWindowID: CGRect] {
        var frames: [CGWindowID: CGRect] = [:]
        for info in windowList {
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            frames[windowID] = frame
        }
        return frames
    }

    /// Keeps a rejection only while the window still sits at the frame we failed to move it from.
    private func pruneRejectedAdjustments(liveWindowFrames: [CGWindowID: CGRect]) {
        rejectedAdjustments = rejectedAdjustments.filter { windowID, rejected in
            liveWindowFrames[windowID] == rejected.frame
        }
    }

    // Finds the AX window element whose on-screen position matches the given CGWindow frame.
    // CGWindowList and AX both use CG coords (top-left origin, Y down), so positions are
    // directly comparable. The focused-window shortcut is tried first for speed; if that
    // misses, all app windows are enumerated and matched by origin with a small tolerance.
    private func findAXWindow(for pid: pid_t, matchingCGFrame frame: CGRect) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(pid)

        func axOrigin(of axWindow: AXUIElement) -> CGPoint? {
            var posRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
                  let posValue = posRef else { return nil }
            var point = CGPoint.zero
            AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
            return point
        }

        func matches(_ axWindow: AXUIElement) -> Bool {
            guard let pos = axOrigin(of: axWindow) else { return false }
            return abs(pos.x - frame.origin.x) < 5 && abs(pos.y - frame.origin.y) < 5
        }

        // Fast path: check focused window first
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let focused = focusedRef,
           matches(focused as! AXUIElement) {
            return (focused as! AXUIElement)
        }

        // Slow path: enumerate all windows
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return nil }

        return axWindows.first { matches($0) }
    }
}

extension AXValue {
    static func from(value: CGPoint, type: AXValueType) -> AXValue? {
        var point = value
        return AXValueCreate(type, &point)
    }
    
    static func from(value: CGSize, type: AXValueType) -> AXValue? {
        var size = value
        return AXValueCreate(type, &size)
    }
}