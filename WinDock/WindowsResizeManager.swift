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
    static let shared = WindowsResizeManager()

    @Published private(set) var isRunning = false
    
    // Cache for dock areas to avoid recalculating too often
    private var dockAreas: [NSScreen: CGRect] = [:]
    private var dockPosition: DockPosition = .bottom
    private var monitoringTimer: Timer?
    
    // Track last update to avoid too frequent updates
    private var lastUpdateTime: TimeInterval = 0
    private let minimumUpdateInterval: TimeInterval = 0.1 // 100ms minimum between updates

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

    private func setupNotifications() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(dockSettingsChanged), name: NSNotification.Name("WinDockPositionChanged"), object: nil)
        notificationCenter.addObserver(self, selector: #selector(screenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func dockSettingsChanged() {
        let enableWindowsResize = UserDefaults.standard.bool(forKey: "enableWindowsResize")
        let currentPosition = DockPosition(rawValue: UserDefaults.standard.string(forKey: "dockPosition") ?? "bottom") ?? .bottom
        
        // Only update if needed
        let positionChanged = currentPosition != dockPosition
        
        if enableWindowsResize && !isRunning {
            start()
        } else if !enableWindowsResize && isRunning {
            stop()
        }
        
        if positionChanged || isRunning {
            updateDockAreaFromSettings()
            // Delay the check slightly to allow animations to complete
            if isRunning {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.checkAllWindows()
                }
            }
        }
    }

    @objc private func screenParametersChanged() {
        updateDockAreaFromSettings()
        if isRunning {
            // Allow time for screen changes to settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.checkAllWindows()
            }
        }
    }

    private func updateDockAreaFromSettings() {
        let newDockPosition = DockPosition(rawValue: UserDefaults.standard.string(forKey: "dockPosition") ?? "bottom") ?? .bottom
        let positionChanged = newDockPosition != dockPosition
        dockPosition = newDockPosition

        // Cache old areas to check if they actually changed
        let oldAreas = dockAreas
        dockAreas.removeAll()

        for (index, screen) in NSScreen.screens.enumerated() {
            let newDockArea = dockFrame(for: dockPosition, screen: screen)
            let oldDockArea = oldAreas[screen]
            
            dockAreas[screen] = newDockArea
            
            if oldDockArea != newDockArea {
                AppLogger.shared.info("Screen \(index) dock area changed: \(String(describing: oldDockArea)) -> \(newDockArea)")
            }
        }
        
        if positionChanged {
            AppLogger.shared.info("Dock position changed to: \(dockPosition.rawValue) across \(NSScreen.screens.count) screens")
        }
    }

    private func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func startPeriodicMonitoring() {
        monitoringTimer?.invalidate()
        // Check more frequently (2 seconds) but with rate limiting in checkAllWindows
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkAllWindows()
            }
        }
        monitoringTimer?.tolerance = 0.2 // Allow some timing flexibility for better power efficiency
        
        // Do an initial check
        DispatchQueue.main.async { [weak self] in
            self?.checkAllWindows()
        }
    }

    func checkAllWindows() {
        guard isRunning, !dockAreas.isEmpty else {
            AppLogger.shared.warning("WindowsResizeManager is not running or dock areas are empty.")
            return
        }

        // Rate limiting: check if enough time has passed since last update
        let currentTime = ProcessInfo.processInfo.systemUptime
        if currentTime - lastUpdateTime < minimumUpdateInterval {
            return
        }
        lastUpdateTime = currentTime

        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        guard let windows = windowList else {
            AppLogger.shared.error("Failed to retrieve window list.")
            return
        }

        AppLogger.shared.info("Checking all windows. Total windows: \(windows.count), Screens: \(NSScreen.screens.count)")

        for windowInfo in windows {
            guard let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let windowFrame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  let app = NSRunningApplication(processIdentifier: pid),
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  app.activationPolicy == .regular,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier,
                  layer == 0 // Only handle normal windows, not utility windows or others
            else {
                continue
            }

            // Skip windows that are likely system UI elements or too small
            let isOnScreen = windowInfo[kCGWindowIsOnscreen as String] as? Bool ?? false
            let alpha = windowInfo[kCGWindowAlpha as String] as? CGFloat ?? 1.0
            if !isOnScreen || alpha < 0.1 || windowFrame.width < 50 || windowFrame.height < 50 {
                continue
            }

            // Find the screen this window is primarily on
            let windowScreen = NSScreen.screens.first { screen in
                let intersection = screen.frame.intersection(windowFrame)
                return !intersection.isNull && (intersection.width * intersection.height) > (windowFrame.width * windowFrame.height * 0.5)
            } ?? NSScreen.main

            if let screen = windowScreen,
               let dockArea = dockAreas[screen],
               windowFrame.intersects(dockArea) {
                AppLogger.shared.info("Window overlaps with dock area on screen \(NSScreen.screens.firstIndex(of: screen) ?? -1). Window: \(windowFrame), Dock area: \(dockArea)")
                adjust(windowFrame: windowFrame, overlapping: dockArea, on: screen, for: app)
            }
        }
    }

    private func adjust(windowFrame: CGRect, overlapping dockArea: CGRect, on screen: NSScreen, for targetApp: NSRunningApplication) {
        var newFrame = windowFrame
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let margin: CGFloat = 4
        
        // Calculate the optimal position based on dock position and overlap
        switch dockPosition {
        case .bottom:
            // If window is mostly below dock area, move it up
            if windowFrame.maxY > dockArea.maxY && windowFrame.minY >= dockArea.minY {
                newFrame.origin.y = dockArea.maxY + margin
            }
            // If window extends below dock area, adjust height
            else if windowFrame.maxY > dockArea.minY {
                newFrame.size.height = min(windowFrame.height, dockArea.minY - windowFrame.minY - margin)
            }
        case .top:
            // If window is mostly above dock area, move it down
            if windowFrame.minY < dockArea.minY && windowFrame.maxY <= dockArea.maxY {
                newFrame.origin.y = dockArea.minY - newFrame.height - margin
            }
            // If window extends above dock area, adjust height
            else if windowFrame.minY < dockArea.maxY {
                let newHeight = min(windowFrame.height, screenFrame.maxY - dockArea.maxY - margin)
                newFrame.origin.y = dockArea.maxY + margin
                newFrame.size.height = newHeight
            }
        case .left:
            // If window is mostly to the left of dock area, move it right
            if windowFrame.maxX > dockArea.maxX && windowFrame.minX >= dockArea.minX {
                newFrame.origin.x = dockArea.maxX + margin
            }
            // If window extends into left dock area, adjust width
            else if windowFrame.maxX > dockArea.minX {
                newFrame.size.width = min(windowFrame.width, dockArea.minX - windowFrame.minX - margin)
            }
        case .right:
            // If window is mostly to the right of dock area, move it left
            if windowFrame.minX < dockArea.minX && windowFrame.maxX <= dockArea.maxX {
                newFrame.origin.x = dockArea.minX - newFrame.width - margin
            }
            // If window extends into right dock area, adjust width
            else if windowFrame.minX < dockArea.maxX {
                let newWidth = min(windowFrame.width, screenFrame.maxX - dockArea.maxX - margin)
                newFrame.origin.x = dockArea.maxX + margin
                newFrame.size.width = newWidth
            }
        }

        // Ensure the window remains within visible screen bounds
        newFrame.origin.x = max(visibleFrame.minX, min(newFrame.origin.x, visibleFrame.maxX - newFrame.width))
        newFrame.origin.y = max(visibleFrame.minY, min(newFrame.origin.y, visibleFrame.maxY - newFrame.height))
        
        // Ensure minimum window size
        newFrame.size.width = max(newFrame.width, 100)
        newFrame.size.height = max(newFrame.height, 100)

        // Check if adjustment is actually needed (avoid unnecessary moves)
        let deltaX = abs(newFrame.origin.x - windowFrame.origin.x)
        let deltaY = abs(newFrame.origin.y - windowFrame.origin.y)
        let deltaW = abs(newFrame.width - windowFrame.width)
        let deltaH = abs(newFrame.height - windowFrame.height)
        
        if deltaX < 1 && deltaY < 1 && deltaW < 1 && deltaH < 1 {
            AppLogger.shared.info("No adjustment needed for window at \(windowFrame.origin) - already positioned correctly")
            return
        }

        AppLogger.shared.info("Adjusting window for app: \(targetApp.localizedName ?? "Unknown") from \(windowFrame) to \(newFrame)")

        // Use Accessibility API to adjust the window
        let appElement = AXUIElementCreateApplication(targetApp.processIdentifier)
        var windowsRef: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else {
            AppLogger.shared.error("Failed to retrieve windows for app: \(targetApp.localizedName ?? "Unknown")")
            return
        }

        for axWindow in axWindows {
            var position = CGPoint.zero
            var size = CGSize.zero

            guard let positionValue = getAXAttribute(for: axWindow, attribute: kAXPositionAttribute as String),
                  let sizeValue = getAXAttribute(for: axWindow, attribute: kAXSizeAttribute as String),
                  AXValueGetValue(positionValue, .cgPoint, &position),
                  AXValueGetValue(sizeValue, .cgSize, &size) else { continue }

            let currentFrame = CGRect(origin: position, size: size)
            
            // Check if this window matches the one we want to adjust (with some tolerance)
            if abs(currentFrame.origin.x - windowFrame.origin.x) < 5 && 
               abs(currentFrame.origin.y - windowFrame.origin.y) < 5 &&
               abs(currentFrame.width - windowFrame.width) < 5 &&
               abs(currentFrame.height - windowFrame.height) < 5 {
                
                // Set new position and size in a single transaction if possible
                if let newPositionValue = AXValue.from(value: newFrame.origin, type: .cgPoint),
                   let newSizeValue = AXValue.from(value: newFrame.size, type: .cgSize) {
                    
                    let posResult = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, newPositionValue)
                    let sizeResult = AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, newSizeValue)
                    
                    if posResult == .success && sizeResult == .success {
                        AppLogger.shared.info("Successfully adjusted window from \(currentFrame) to: \(newFrame) for app: \(targetApp.localizedName ?? "Unknown")")
                    } else {
                        AppLogger.shared.error("Failed to adjust window. Position result: \(posResult), Size result: \(sizeResult)")
                    }
                } else {
                    AppLogger.shared.error("Failed to create AXValues for new position/size")
                }
                return // Found and adjusted the matching window
            }
        }
        
        AppLogger.shared.warning("Could not find matching window to adjust for frame: \(windowFrame) in app: \(targetApp.localizedName ?? "Unknown")")
    }

    private func getAXAttribute(for element: AXUIElement, attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as! AXValue?
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

