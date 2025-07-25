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
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.resizeAndMoveWindowsIfNeeded()
        }
    }

    func resizeAndMoveWindowsIfNeeded() {
        guard isRunning, !dockAreas.isEmpty else {
            AppLogger.shared.warning("WindowsResizeManager is not running or dock areas are empty.")
            return
        }

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            AppLogger.shared.error("Failed to retrieve window list.")
            return
        }


        let filteredWindows = windowList.compactMap { windowInfo -> (windowInfo: [String: Any], pid: pid_t, windowFrame: CGRect, app: NSRunningApplication)? in
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
            else {
            return nil
            }
            
            return (windowInfo: windowInfo, pid: pid, windowFrame: windowFrame, app: app)
        }
        guard !filteredWindows.isEmpty else {
            return
        }
        // AppLogger.shared.info("Checking windows: \(filteredWindows.count), Screens: \(NSScreen.screens.count), Apps: \(Set(filteredWindows.map { $0.app.localizedName ?? "Unknown" }).joined(separator: ", "))")

        for filteredWindow in filteredWindows {
            let windowFrame = filteredWindow.windowFrame
            let app = filteredWindow.app

            // Check all screens to see if this window overlaps with any dock area
            for (screen, dockArea) in dockAreas {
                // Check if window is on this screen and overlaps with dock area
                if screen.frame.intersects(windowFrame) && windowFrame.intersects(dockArea) {
                    var newFrame = windowFrame
                    let screenFrame = screen.frame
                    let margin: CGFloat = 15
                    let maxHeight = screenFrame.height - dockArea.height - margin
                    let maxWidth = screenFrame.width - dockArea.width - margin
                    var resized = false
                    if dockPosition == .bottom || dockPosition == .top {
                        if maxHeight < newFrame.height {
                            newFrame.size.height = maxHeight
                            resized = true
                        }
                    } else {
                        if maxWidth < newFrame.width {
                            newFrame.size.width = maxWidth
                            resized = true
                        }
                    }
                    
                    var needToMove = false
                    if !resized {
                        switch dockPosition {
                            case .bottom:
                                if newFrame.minY > dockArea.maxY {
                                    needToMove = true
                                }
                            case .top:
                                if dockArea.maxY < screenFrame.minY {
                                    needToMove = true
                                }
                            case .left:
                                if dockArea.minX > screenFrame.maxX {
                                    needToMove = true
                                }
                            case .right:
                                if dockArea.maxX < screenFrame.minX {
                                    needToMove = true
                                }
                        }
                    }

                    if !resized && !needToMove {
                        return
                    }

                    switch dockPosition {
                        case .bottom:
                            newFrame.origin.y = dockArea.maxY
                        case .top:
                            newFrame.origin.y = screenFrame.minY
                        case .left:
                            newFrame.origin.x = dockArea.maxX
                        case .right:
                            newFrame.origin.x = screenFrame.minX
                    }
                    
                    AppLogger.shared.info("Adjusting window for app \(app.localizedName ?? "Unknown") from \(windowFrame) to \(newFrame) on screen \(screen.frame). Resized: \(resized), NeedToMove: \(needToMove)")
                    
                    // Get the application's accessibility element
                    let axApp = AXUIElementCreateApplication(app.processIdentifier)
                    
                    // Get the focused window
                    var focusedWindowRef: CFTypeRef?
                    let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
                    
                    if result == .success, let focusedWindow = focusedWindowRef as! AXUIElement? {
                        if resized {
                            if AXUIElementSetAttributeValue(focusedWindow, kAXSizeAttribute as CFString, AXValue.from(value: newFrame.size, type: .cgSize)!) == .success {
                                AppLogger.shared.info("Successfully adjusted window size.")
                            } else {
                                AppLogger.shared.error("Failed to adjust window size for app \(app.localizedName ?? "Unknown")")
                            }
                        }
                        
                        if needToMove {
                            if AXUIElementSetAttributeValue(focusedWindow, kAXPositionAttribute as CFString, AXValue.from(value: newFrame.origin, type: .cgPoint)!) == .success {
                                AppLogger.shared.info("Successfully moved window to new position.")
                            } else {
                                AppLogger.shared.error("Failed to move window for app \(app.localizedName ?? "Unknown")")
                            }
                        }
                    } else {
                        AppLogger.shared.error("Failed to get focused window for app \(app.localizedName ?? "Unknown")")
                    }
                }
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