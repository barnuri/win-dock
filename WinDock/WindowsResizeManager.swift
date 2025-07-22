import Foundation
import AppKit
import CoreGraphics

class WindowsResizeManager: ObservableObject {
    static let shared = WindowsResizeManager()
    
    private var isRunning = false
    private var observers: [AXObserver] = []
    private var observerInfos: [(observer: AXObserver, app: NSRunningApplication, element: AXUIElement)] = []
    private var dockAreas: [NSScreen: CGRect] = [:]
    private var dockPosition: DockPosition = .bottom
    private var monitoringTimer: Timer?
    private var recentlyAdjustedWindows: Set<CGWindowID> = []
    private var lastAdjustmentTime: [CGWindowID: Date] = [:]
    
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
            let errorMessage = "WindowsResizeManager failed to start: Accessibility permissions not granted"
            AppLogger.shared.error(errorMessage)
            requestAccessibilityPermissions()
            return
        }
        
        isRunning = true
        updateDockAreaFromSettings()
        setupWindowMonitoring()
        startPeriodicMonitoring()
        AppLogger.shared.info("WindowsResizeManager started successfully")
    }
    
    func stop() {
        guard isRunning else { return }
        
        isRunning = false
        cleanupObservers()
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        AppLogger.shared.info("WindowsResizeManager stopped")
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dockPositionChanged),
            name: NSNotification.Name("WinDockPositionChanged"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationLaunched),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationTerminated),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }
    
    @objc private func dockPositionChanged() {
        updateDockAreaFromSettings()
        if isRunning {
            checkAllVisibleWindows()
        }
    }
    
    @objc private func userDefaultsChanged() {
        updateDockAreaFromSettings()
        if isRunning {
            checkAllVisibleWindows()
        }
    }
    
    @objc private func screenParametersChanged() {
        updateDockAreaFromSettings()
        if isRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.setupWindowMonitoring()
                self.checkAllVisibleWindows()
            }
        }
    }
    
    @objc private func applicationLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.addObserverForApplication(app)
        }
    }
    
    @objc private func applicationTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        
        removeObserverForApplication(app)
    }
    
    private func updateDockAreaFromSettings() {
        let dockPositionStr = UserDefaults.standard.string(forKey: "dockPosition") ?? "bottom"
        dockPosition = DockPosition(rawValue: dockPositionStr) ?? .bottom
        
        // Clear existing dock areas
        dockAreas.removeAll()
        
        // Calculate dock area for each screen
        for screen in NSScreen.screens {
            let dockArea = dockFrame(for: dockPosition, screen: screen)
            dockAreas[screen] = dockArea
            AppLogger.shared.info("Updated dock area for screen \(screen.localizedName): \(dockArea) for position: \(dockPosition.rawValue)")
        }
    }
    
    private func checkAccessibilityPermissions() -> Bool {
        let isPermitted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary)
        if !isPermitted {
            AppLogger.shared.error("Accessibility permissions not granted for WindowsResizeManager")
        }
        return isPermitted
    }
    
    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        
        if !isTrusted {
            DispatchQueue.main.async {
                self.showAccessibilityAlert()
            }
        }
    }
    
    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "WinDock needs accessibility permissions to resize windows and prevent them from overlapping the dock area. Please enable accessibility access in System Settings > Privacy & Security > Accessibility."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        
        AppLogger.shared.error("Accessibility permissions alert shown to user")
    }
    
    private func setupWindowMonitoring() {
        cleanupObservers()
        
        let runningApps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular && app.bundleIdentifier != nil
        }
        
        for app in runningApps {
            addObserverForApplication(app)
        }
        
        AppLogger.shared.info("Set up window monitoring for \(runningApps.count) applications")
    }
    
    private func addObserverForApplication(_ app: NSRunningApplication) {
        guard app.bundleIdentifier?.contains("WinDock") != true else { return }
        guard app.activationPolicy == .regular else { return }
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var observer: AXObserver?
        
        let result = AXObserverCreate(app.processIdentifier, axObserverCallback, &observer)
        guard result == .success, let observer = observer else {
            AppLogger.shared.error("Failed to create AX observer for app: \(app.bundleIdentifier ?? "unknown")")
            return
        }
        
        let notifications = [
            kAXMovedNotification,
            kAXResizedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification,
            kAXApplicationActivatedNotification,
            kAXWindowCreatedNotification
        ]
        
        for notification in notifications {
            let addResult = AXObserverAddNotification(observer, appElement, notification as CFString, nil)
            if addResult != .success {
                AppLogger.shared.error("Failed to add AX notification \(notification) for app \(app.bundleIdentifier ?? "unknown")")
            }
        }
        
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        
        observers.append(observer)
        observerInfos.append((observer: observer, app: app, element: appElement))
        
        AppLogger.shared.info("Added AX observer for app: \(app.bundleIdentifier ?? "unknown")")
    }
    
    private func removeObserverForApplication(_ app: NSRunningApplication) {
        observerInfos.removeAll { info in
            if info.app.processIdentifier == app.processIdentifier {
                let observer = info.observer
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
                
                if let index = observers.firstIndex(of: observer) {
                    observers.remove(at: index)
                }
                
                AppLogger.shared.info("Removed AX observer for app: \(app.bundleIdentifier ?? "unknown")")
                return true
            }
            return false
        }
    }
    
    private func cleanupObservers() {
        for observer in observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers.removeAll()
        observerInfos.removeAll()
        
        AppLogger.shared.info("Cleaned up all AX observers")
    }
    
    private func startPeriodicMonitoring() {
        monitoringTimer?.invalidate()
        
        // Use a longer interval (5 seconds) to prevent frequent checks
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.cleanupOldAdjustmentRecords()
            self?.checkAllVisibleWindows()
        }
    }
    
    private func cleanupOldAdjustmentRecords() {
        let cutoffTime = Date().addingTimeInterval(-30.0) // Remove records older than 30 seconds
        lastAdjustmentTime = lastAdjustmentTime.filter { _, date in
            date > cutoffTime
        }
    }
    
    func checkAllVisibleWindows() {
        guard isRunning else { return }
        
        // Check if any dock areas are defined
        if dockAreas.isEmpty {
            updateDockAreaFromSettings()
            // If still empty, nothing to do
            if dockAreas.isEmpty {
                return
            }
        }
        
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        
        guard let windows = windowList else {
            AppLogger.shared.error("Failed to get window list for overlap checking")
            return
        }
        
        var adjustedCount = 0
        
        // Create a set to track apps we've already checked, to avoid duplicate work
        var processedPIDs = Set<pid_t>()
        
        for windowInfo in windows {
            // Skip if window has no bounds or layer is below threshold (likely invisible or background window)
            guard let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat,
                  let windowNumber = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer < 100 else { continue } // Skip high-layer windows (menu, helper, etc)
            
            // Skip windows that are too small (likely utility windows, tooltips, etc)
            if width < 100 || height < 100 { continue }
            
            // Get window app
            guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
            
            // Skip our own app and non-regular apps
            if let bundleId = app.bundleIdentifier, 
               bundleId.contains("WinDock") || app.activationPolicy != .regular {
                continue
            }
            
            // Skip recently adjusted windows
            if let lastAdjusted = lastAdjustmentTime[windowNumber],
               Date().timeIntervalSince(lastAdjusted) < 5.0 {
                continue
            }
            
            // Create window rect
            let windowRect = CGRect(x: x, y: y, width: width, height: height)
            
            // Find overlapping dock area
            var overlappingDockArea: CGRect?
            var overlappingScreen: NSScreen?
            
            for (screen, dockArea) in dockAreas {
                if windowRect.intersects(dockArea) {
                    overlappingDockArea = dockArea
                    overlappingScreen = screen
                    break
                }
            }
            
            // Adjust window if it overlaps with dock
            if let dockArea = overlappingDockArea, let screen = overlappingScreen {
                if adjustWindowForDockOverlap(windowRect: windowRect, windowNumber: windowNumber, pid: pid, dockArea: dockArea, screen: screen) {
                    adjustedCount += 1
                    
                    // Limit adjustments per check to avoid heavy processing
                    if adjustedCount >= 3 {
                        break
                    }
                }
            }
        }
        
        if adjustedCount > 0 {
            AppLogger.shared.info("Adjusted \(adjustedCount) windows to avoid dock overlap")
        }
    }
    
    private func adjustWindowForDockOverlap(windowRect: CGRect, windowNumber: CGWindowID, pid: pid_t, dockArea: CGRect, screen: NSScreen) -> Bool {
        let screenFrame = screen.frame
        var adjustedRect = windowRect
        let margin: CGFloat = 10.0 // Small margin to ensure windows don't touch the dock
        
        // Check if this window was recently adjusted (within 5 seconds)
        if let lastAdjusted = lastAdjustmentTime[windowNumber], 
           Date().timeIntervalSince(lastAdjusted) < 5.0 {
            // Skip windows that were very recently adjusted to break potential loops
            return false
        }
        
        // Calculate significant overlap threshold - only adjust if overlap is meaningful
        let significantOverlapThreshold: CGFloat = 20.0
        var hasSignificantOverlap = false
        var overlapArea: CGFloat = 0
        
        // Calculate the intersection area to determine overlap severity
        let intersection = windowRect.intersection(dockArea)
        if !intersection.isEmpty {
            overlapArea = intersection.width * intersection.height
            hasSignificantOverlap = (overlapArea > significantOverlapThreshold)
            
            // Only log if there's meaningful overlap
            if hasSignificantOverlap {
                AppLogger.shared.info("Window overlap with dock: \(overlapArea) points² - Window: \(windowRect), Dock: \(dockArea)")
            }
        }
        
        // Only proceed if there's significant overlap
        guard hasSignificantOverlap else {
            return false
        }
        
        // Calculate dock boundaries and adjust windows
        // Minimum allowed dimensions for windows after resizing
        let minWindowWidth: CGFloat = 400
        let minWindowHeight: CGFloat = 300
        
        switch dockPosition {
        case .bottom:
            // For bottom dock: Try to move window up, resize if needed
            let maxY = dockArea.minY - margin
            if adjustedRect.maxY > maxY {
                // Calculate available height above dock
                let availableHeight = maxY - screenFrame.minY
                
                if adjustedRect.height <= availableHeight || availableHeight >= minWindowHeight {
                    // Enough space to move the window above the dock
                    let newY = maxY - adjustedRect.height
                    adjustedRect.origin.y = max(newY, screenFrame.minY)
                } else {
                    // Not enough space above dock, resize the window to fit
                    adjustedRect.size.height = max(availableHeight, minWindowHeight)
                    adjustedRect.origin.y = screenFrame.minY
                }
            }
        case .top:
            // For top dock: Try to move window down, resize if needed
            let minY = dockArea.maxY + margin
            if adjustedRect.minY < minY {
                // Calculate available height below dock
                let availableHeight = screenFrame.maxY - minY
                
                if adjustedRect.height <= availableHeight || availableHeight >= minWindowHeight {
                    // Enough space to move the window below the dock
                    adjustedRect.origin.y = minY
                } else {
                    // Not enough space below dock, resize the window to fit
                    adjustedRect.size.height = max(availableHeight, minWindowHeight)
                    adjustedRect.origin.y = minY
                }
            }
        case .left:
            // For left dock: Try to move window right, resize if needed
            let minX = dockArea.maxX + margin
            if adjustedRect.minX < minX {
                // Calculate available width to the right of dock
                let availableWidth = screenFrame.maxX - minX
                
                if adjustedRect.width <= availableWidth || availableWidth >= minWindowWidth {
                    // Enough space to move the window to the right of the dock
                    adjustedRect.origin.x = minX
                } else {
                    // Not enough space to the right, resize the window to fit
                    adjustedRect.size.width = max(availableWidth, minWindowWidth)
                    adjustedRect.origin.x = minX
                }
            }
        case .right:
            // For right dock: Try to move window left, resize if needed
            let maxX = dockArea.minX - margin
            if adjustedRect.maxX > maxX {
                // Calculate available width to the left of dock
                let availableWidth = maxX - screenFrame.minX
                
                if adjustedRect.width <= availableWidth || availableWidth >= minWindowWidth {
                    // Enough space to move the window to the left of the dock
                    let newX = maxX - adjustedRect.width
                    adjustedRect.origin.x = max(newX, screenFrame.minX)
                } else {
                    // Not enough space to the left, resize the window to fit
                    adjustedRect.size.width = max(availableWidth, minWindowWidth)
                    adjustedRect.origin.x = screenFrame.minX
                }
            }
        }
        
        // Ensure the window stays within screen bounds
        if adjustedRect.maxX > screenFrame.maxX {
            adjustedRect.origin.x = screenFrame.maxX - adjustedRect.width
        }
        if adjustedRect.maxY > screenFrame.maxY {
            adjustedRect.origin.y = screenFrame.maxY - adjustedRect.height
        }
        if adjustedRect.minX < screenFrame.minX {
            adjustedRect.origin.x = screenFrame.minX
        }
        if adjustedRect.minY < screenFrame.minY {
            adjustedRect.origin.y = screenFrame.minY
        }
        
        // Check for meaningful changes in position or size (at least 5 pixels)
        let minMeaningfulChange: CGFloat = 5.0
        let positionChanged = abs(adjustedRect.origin.x - windowRect.origin.x) >= minMeaningfulChange ||
                              abs(adjustedRect.origin.y - windowRect.origin.y) >= minMeaningfulChange
        let sizeChanged = abs(adjustedRect.width - windowRect.width) >= minMeaningfulChange ||
                          abs(adjustedRect.height - windowRect.height) >= minMeaningfulChange
        
        if !positionChanged && !sizeChanged {
            return false
        }
        
        // Record the attempted adjustment before trying to actually apply it
        lastAdjustmentTime[windowNumber] = Date()
        
        // Try to adjust window using Accessibility API
        let app = NSRunningApplication(processIdentifier: pid)
        let appElement = AXUIElementCreateApplication(pid)
        
        var windowListRef: CFTypeRef?
        let getWindowsResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowListRef)
        
        guard getWindowsResult == .success,
              let windowList = windowListRef as? [AXUIElement] else {
            AppLogger.shared.error("Failed to get windows for app PID: \(pid)")
            return false
        }
        
        // Find the matching window by comparing positions (approximate)
        for window in windowList {
            var positionRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            
            if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
               AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
               let positionValue = positionRef,
               let sizeValue = sizeRef,
               CFGetTypeID(positionValue) == AXValueGetTypeID(),
               CFGetTypeID(sizeValue) == AXValueGetTypeID() {
                
                var currentPosition = CGPoint.zero
                var currentSize = CGSize.zero
                
                if AXValueGetValue(positionValue as! AXValue, .cgPoint, &currentPosition) &&
                   AXValueGetValue(sizeValue as! AXValue, .cgSize, &currentSize) {
                    
                    let currentRect = CGRect(origin: currentPosition, size: currentSize)
                    
                    // Check if this is approximately the same window (within 15 pixels)
                    // Using a relaxed match to ensure we find the right window
                    if abs(currentRect.origin.x - windowRect.origin.x) < 15.0 &&
                       abs(currentRect.origin.y - windowRect.origin.y) < 15.0 &&
                       abs(currentRect.width - windowRect.width) < 15.0 &&
                       abs(currentRect.height - windowRect.height) < 15.0 {
                        
                        // Get the app name for better logging
                        let appName = app?.localizedName ?? "unknown app"
                        let bundleId = app?.bundleIdentifier ?? "unknown"
                        
                        // Prepare position and size values
                        let newPosition = AXValue.from(value: adjustedRect.origin, type: .cgPoint)
                        let newSize = AXValue.from(value: adjustedRect.size, type: .cgSize)
                        
                        var positionChanged = false
                        var sizeChanged = false
                        
                        // Apply position changes if needed
                        if abs(adjustedRect.origin.x - currentRect.origin.x) >= 1.0 || 
                           abs(adjustedRect.origin.y - currentRect.origin.y) >= 1.0 {
                            
                            let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, newPosition)
                            if positionResult == .success {
                                positionChanged = true
                            } else {
                                AppLogger.shared.error("Failed to move \(appName) window (\(bundleId)), error: \(positionResult.rawValue)")
                            }
                        }
                        
                        // Apply size changes if needed
                        if abs(adjustedRect.width - currentRect.width) >= 1.0 || 
                           abs(adjustedRect.height - currentRect.height) >= 1.0 {
                            
                            let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, newSize)
                            if sizeResult == .success {
                                sizeChanged = true
                            } else {
                                AppLogger.shared.error("Failed to resize \(appName) window (\(bundleId)), error: \(sizeResult.rawValue)")
                            }
                        }
                        
                        // Log the changes
                        if positionChanged && sizeChanged {
                            AppLogger.shared.info("Successfully moved and resized \(appName) window from \(windowRect) to \(adjustedRect) to avoid dock overlap")
                            return true
                        } else if positionChanged {
                            AppLogger.shared.info("Successfully moved \(appName) window from \(windowRect.origin) to \(adjustedRect.origin) to avoid dock overlap")
                            return true
                        } else if sizeChanged {
                            AppLogger.shared.info("Successfully resized \(appName) window from \(windowRect.size) to \(adjustedRect.size) to avoid dock overlap")
                            return true
                        }
                        break
                    }
                }
            }
        }
        
        return false
    }
}

private func axObserverCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    userData: UnsafeMutableRawPointer?
) {
    // Handle window movement and resize events
    let notificationName = notification as String
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        // Give the window a moment to settle before checking
        WindowsResizeManager.shared.checkAllVisibleWindows()
    }
    
    AppLogger.shared.info("Window event detected: \(notificationName)")
}

extension AXValue {
    static func from(value: CGPoint, type: AXValueType) -> AXValue {
        var point = value
        return AXValueCreate(type, &point)!
    }
    
    static func from(value: CGSize, type: AXValueType) -> AXValue {
        var size = value
        return AXValueCreate(type, &size)!
    }
}
