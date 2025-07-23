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
            checkAllWindows()
        }
    }

    @objc private func screenParametersChanged() {
        updateDockAreaFromSettings()
        if isRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.checkAllWindows()
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
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkAllWindows()
        }
    }

    func checkAllWindows() {
        guard isRunning, !dockAreas.isEmpty else {
            AppLogger.shared.warning("WindowsResizeManager is not running or dock areas are empty.")
            return
        }

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            AppLogger.shared.error("Failed to retrieve window list.")
            return
        }

        AppLogger.shared.info("Checking all windows. Total windows: \(windowList.count), Screens: \(NSScreen.screens.count)")

        for windowInfo in windowList {
            guard 
                let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                let windowFrame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                let app = NSRunningApplication(processIdentifier: pid),
                app.activationPolicy == .regular,
                app.bundleIdentifier != Bundle.main.bundleIdentifier 
            else {
                continue
            }

            // Check all screens to see if this window overlaps with any dock area
            for (screen, dockArea) in dockAreas {
                // Check if window is on this screen and overlaps with dock area
                if screen.frame.intersects(windowFrame) && windowFrame.intersects(dockArea) {
                    let screenIndex = NSScreen.screens.firstIndex(of: screen) ?? -1
                    AppLogger.shared.info("Window overlaps with dock area on screen \(screenIndex). Window: \(windowFrame), Dock area: \(dockArea)")
                    adjust(windowFrame: windowFrame, overlapping: dockArea, on: screen, for: app)
                    break // Only adjust once per window
                }
            }
        }
    }

    private func adjust(windowFrame: CGRect, overlapping dockArea: CGRect, on screen: NSScreen, for targetApp: NSRunningApplication) {
        var newFrame = windowFrame
        let screenFrame = screen.frame
        let margin: CGFloat = 4

        switch dockPosition {
        case .bottom:
            newFrame.origin.y = dockArea.maxY + margin
        case .top:
            newFrame.origin.y = dockArea.minY - newFrame.height - margin
        case .left:
            newFrame.origin.x = dockArea.maxX + margin
        case .right:
            newFrame.origin.x = dockArea.minX - newFrame.width - margin
        }

        // Ensure the window remains within screen bounds after moving
        if newFrame.maxX > screenFrame.maxX {
            newFrame.origin.x = screenFrame.maxX - newFrame.width
        }
        if newFrame.minX < screenFrame.minX {
            newFrame.origin.x = screenFrame.minX
        }
        if newFrame.maxY > screenFrame.maxY {
            newFrame.origin.y = screenFrame.maxY - newFrame.height
        }
        if newFrame.minY < screenFrame.minY {
            newFrame.origin.y = screenFrame.minY
        }

        // Check if adjustment is actually needed (avoid unnecessary moves)
        let deltaX = abs(newFrame.origin.x - windowFrame.origin.x)
        let deltaY = abs(newFrame.origin.y - windowFrame.origin.y)
        if deltaX < 1 && deltaY < 1 {
            AppLogger.shared.info("No adjustment needed for window at \(windowFrame.origin) - already positioned correctly")
            return
        }

        AppLogger.shared.info("Adjusting window for app: \(targetApp.localizedName ?? "Unknown") from \(windowFrame.origin) to \(newFrame.origin)")

        // Directly work with the target application
        let appElement = AXUIElementCreateApplication(targetApp.processIdentifier)
        var windowsRef: CFTypeRef?

        guard 
            AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
            let axWindows = windowsRef as? [AXUIElement] 
        else {
            AppLogger.shared.error("Failed to retrieve windows for app: \(targetApp.localizedName ?? "Unknown")")
            return
        }

        for axWindow in axWindows {
            var position = CGPoint.zero
            var size = CGSize.zero

            if 
                let positionValue = getAXAttribute(for: axWindow, attribute: kAXPositionAttribute as String),
                let sizeValue = getAXAttribute(for: axWindow, attribute: kAXSizeAttribute as String),
                AXValueGetValue(positionValue, .cgPoint, &position),
                AXValueGetValue(sizeValue, .cgSize, &size) 
            {
                let currentFrame = CGRect(origin: position, size: size)
                
                // Check if this window matches the one we want to adjust
                if abs(currentFrame.origin.x - windowFrame.origin.x) < 5 &&
                   abs(currentFrame.origin.y - windowFrame.origin.y) < 5 &&
                   abs(currentFrame.width - windowFrame.width) < 5 &&
                   abs(currentFrame.height - windowFrame.height) < 5 
                {
                    if let newPositionValue = AXValue.from(value: newFrame.origin, type: .cgPoint) {
                        let result = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, newPositionValue)
                        if result == .success {
                            AppLogger.shared.info("Successfully adjusted window position from \(currentFrame.origin) to \(newFrame.origin) for app: \(targetApp.localizedName ?? "Unknown")")
                        } else {
                            AppLogger.shared.error("Failed to set window position. AX result: \(result)")
                        }
                    } else {
                        AppLogger.shared.error("Failed to create AXValue for new position.")
                    }
                    return
                }
            }
        }

        AppLogger.shared.warning("Could not find matching window to adjust for frame: \(windowFrame) in app: \(targetApp.localizedName ?? "Unknown")")
    }

    private func getAXAttribute(for element: AXUIElement, attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let axValue = value else {
            return nil
        }
        return axValue as! AXValue
    }
}

// MARK: - AXValue Helper

extension AXValue {
    static func from(value: CGPoint, type: AXValueType) -> AXValue? {
        var point = value
        return AXValueCreate(type, &point)
    }
}