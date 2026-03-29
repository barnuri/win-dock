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
    
    // References to other managers for state checking
    private let fullscreenManager = FullscreenDetectionManager.shared
    private let macOSDockManager = MacOSDockManager()

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
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
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

        if shouldDisableResizing() {
            return
        }

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            AppLogger.shared.error("Failed to retrieve window list.")
            return
        }

        let filteredWindows = windowList.compactMap { windowInfo -> (pid: pid_t, windowFrame: CGRect, app: NSRunningApplication)? in
            guard
                let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                let windowFrame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                let app = NSRunningApplication(processIdentifier: pid),
                app.activationPolicy == .regular,
                app.bundleIdentifier != Bundle.main.bundleIdentifier,
                !app.isTerminated,
                !app.isHidden,
                windowInfo[kCGWindowIsOnscreen as String] as? Bool == true,
                windowInfo[kCGWindowLayer as String] as? Int == 0
            else { return nil }
            return (pid: pid, windowFrame: windowFrame, app: app)
        }
        guard !filteredWindows.isEmpty else { return }

        // CGWindowListCopyWindowInfo returns frames in CG screen coordinates (origin at
        // top-left of main screen, Y increases downward).  dockFrame() / NSScreen use
        // Cocoa coordinates (origin at bottom-left, Y increases upward).  Convert the
        // Cocoa dock area and screen frame to CG coordinates before comparing.
        guard let mainScreenHeight = NSScreen.main?.frame.height else { return }

        for window in filteredWindows {
            let windowFrame = window.windowFrame
            let app = window.app

            for (screen, cocoaDockArea) in dockAreas {
                // Convert Cocoa rect → CG rect (flip Y axis)
                let cgDockArea = CGRect(
                    x: cocoaDockArea.origin.x,
                    y: mainScreenHeight - cocoaDockArea.origin.y - cocoaDockArea.height,
                    width: cocoaDockArea.width,
                    height: cocoaDockArea.height
                )
                let cgScreenFrame = CGRect(
                    x: screen.frame.origin.x,
                    y: mainScreenHeight - screen.frame.origin.y - screen.frame.height,
                    width: screen.frame.width,
                    height: screen.frame.height
                )

                guard cgScreenFrame.intersects(windowFrame) && windowFrame.intersects(cgDockArea) else {
                    continue
                }

                var newFrame = windowFrame
                let margin: CGFloat = 15

                // Resize if the window is too tall / too wide to fit beside the dock
                if dockPosition == .bottom || dockPosition == .top {
                    let maxHeight = cgScreenFrame.height - cgDockArea.height - margin
                    if newFrame.height > maxHeight {
                        newFrame.size.height = maxHeight
                    }
                } else {
                    let maxWidth = cgScreenFrame.width - cgDockArea.width - margin
                    if newFrame.width > maxWidth {
                        newFrame.size.width = maxWidth
                    }
                }

                // Reposition so the window no longer overlaps the dock.
                // All values are in CG coordinates (Y↓, top-left origin).
                switch dockPosition {
                case .bottom:
                    // Dock occupies high Y values; place window so its bottom edge
                    // (origin.y + height) sits exactly at the dock's top edge.
                    newFrame.origin.y = cgDockArea.minY - newFrame.height
                case .top:
                    // Dock occupies low Y values; place window so its top edge
                    // starts at the dock's bottom edge.
                    newFrame.origin.y = cgDockArea.maxY
                case .left:
                    newFrame.origin.x = cgDockArea.maxX
                case .right:
                    newFrame.origin.x = cgDockArea.minX - newFrame.width
                }

                guard newFrame != windowFrame else { continue }

                AppLogger.shared.info("Adjusting window for \(app.localizedName ?? "Unknown") from \(windowFrame) to \(newFrame)")

                let axApp = AXUIElementCreateApplication(app.processIdentifier)
                var focusedWindowRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
                      let focusedWindow = focusedWindowRef as! AXUIElement? else {
                    AppLogger.shared.error("Failed to get focused window for \(app.localizedName ?? "Unknown")")
                    continue
                }

                if newFrame.size != windowFrame.size {
                    AXUIElementSetAttributeValue(focusedWindow, kAXSizeAttribute as CFString, AXValue.from(value: newFrame.size, type: .cgSize)!)
                }
                AXUIElementSetAttributeValue(focusedWindow, kAXPositionAttribute as CFString, AXValue.from(value: newFrame.origin, type: .cgPoint)!)
            }
        }
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