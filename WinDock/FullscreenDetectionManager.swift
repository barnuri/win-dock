import AppKit
import SwiftUI

class FullscreenDetectionManager: ObservableObject {
    static let shared = FullscreenDetectionManager()
    
    @Published private(set) var hasFullscreenWindow = false
    private var monitoringTimer: Timer?
    private var isRunning = false
    
    private init() {}
    
    func startMonitoring() {
        guard !isRunning else { return }
        
        isRunning = true
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForFullscreenWindows()
        }
        
        // Also listen for app activation changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        
        AppLogger.shared.info("FullscreenDetectionManager started monitoring")
    }
    
    func stopMonitoring() {
        guard isRunning else { return }
        
        isRunning = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        NotificationCenter.default.removeObserver(self)
        AppLogger.shared.info("FullscreenDetectionManager stopped monitoring")
    }
    
    @objc private func appDidBecomeActive() {
        // Check immediately when an app becomes active
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.checkForFullscreenWindows()
        }
    }
    
    @objc private func appDidResignActive() {
        // Check when an app resigns active status
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.checkForFullscreenWindows()
        }
    }
    
    private func checkForFullscreenWindows() {
        let previousState = hasFullscreenWindow
        hasFullscreenWindow = detectFullscreenWindow()
        
        if previousState != hasFullscreenWindow {
            AppLogger.shared.info("Fullscreen state changed: \(hasFullscreenWindow)")
            NotificationCenter.default.post(
                name: NSNotification.Name("FullscreenStateChanged"),
                object: nil,
                userInfo: ["hasFullscreen": hasFullscreenWindow]
            )
        }
    }
    
    private func detectFullscreenWindow() -> Bool {
        // Get the main screen bounds
        guard let mainScreen = NSScreen.main else { return false }
        let screenBounds = mainScreen.frame
        
        // Get all on-screen windows
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        
        for windowInfo in windowList {
            // Skip WinDock windows
            if let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
               let app = NSRunningApplication(processIdentifier: ownerPID),
               app.bundleIdentifier == Bundle.main.bundleIdentifier {
                continue
            }
            
            // Check if window covers the entire screen
            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            
            // Check if the window is on-screen and has full alpha
            guard let isOnScreen = windowInfo[kCGWindowIsOnscreen as String] as? Bool,
                  isOnScreen,
                  let alpha = windowInfo[kCGWindowAlpha as String] as? CGFloat,
                  alpha > 0.9,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer >= 0 else {
                continue
            }
            
            // Check if window covers most or all of the screen (allowing for small margins)
            let tolerance: CGFloat = 10
            let coversWidth = bounds.width >= screenBounds.width - tolerance
            let coversHeight = bounds.height >= screenBounds.height - tolerance
            let positionedAtTop = bounds.origin.y <= tolerance
            let positionedAtLeft = bounds.origin.x <= tolerance
            
            if coversWidth && coversHeight && positionedAtTop && positionedAtLeft {
                // Additional check: make sure it's not just a maximized window with title bar
                let isActuallyFullscreen = bounds.height >= screenBounds.height - 5
                
                if isActuallyFullscreen {
                    return true
                }
            }
        }
        
        // Also check if any app is in fullscreen mode via NSApplication
        for app in NSWorkspace.shared.runningApplications {
            if app.bundleIdentifier != Bundle.main.bundleIdentifier && app.activationPolicy == .regular {
                // Try to detect fullscreen mode using app-specific detection
                if isAppInFullscreenMode(app) {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func isAppInFullscreenMode(_ app: NSRunningApplication) -> Bool {
        // Use AppleScript to check if the app is in fullscreen mode
        guard let appName = app.localizedName else { return false }
        
        let script = """
        tell application "System Events"
            try
                tell process "\(appName)"
                    set windowExists to exists window 1
                    if windowExists then
                        set windowBounds to get position of window 1
                        set windowSize to get size of window 1
                        set {screenWidth, screenHeight} to get size of desktop
                        
                        set {winX, winY} to windowBounds
                        set {winW, winH} to windowSize
                        
                        -- Check if window covers the full screen (with small tolerance)
                        if winX <= 5 and winY <= 5 and winW >= (screenWidth - 10) and winH >= (screenHeight - 10) then
                            return true
                        end if
                    end if
                end tell
            on error
                return false
            end try
            return false
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            if error == nil {
                return result.booleanValue
            }
        }
        
        return false
    }
    
    deinit {
        stopMonitoring()
    }
}
