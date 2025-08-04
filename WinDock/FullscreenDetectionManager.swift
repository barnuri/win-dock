import AppKit
import SwiftUI

class FullscreenDetectionManager: ObservableObject {
    static let shared = FullscreenDetectionManager()
    
    @Published private(set) var hasFullscreenWindow = false
    private var monitoringTimer: Timer?
    private var isRunning = false
    private var startupTime: Date?
    
    private init() {}
    
    func startMonitoring() {
        guard !isRunning else { return }
        
        isRunning = true
        startupTime = Date()
        
        // Add delay to prevent false positives during startup
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            // Reduce frequency from 1.0s to 3.0s for better performance
            self.monitoringTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                self?.checkForFullscreenWindows()
            }
            
            // Run initial check after delay
            self.checkForFullscreenWindows()
        }
        
        // Listen for app activation changes for more immediate updates
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
        // Skip detection for the first 10 seconds after startup to avoid false positives
        if let startupTime = startupTime, Date().timeIntervalSince(startupTime) < 10.0 {
            return
        }
        
        let previousState = hasFullscreenWindow
        hasFullscreenWindow = detectFullscreenWindow()
        
        if previousState != hasFullscreenWindow {
            AppLogger.shared.info("Fullscreen state changed: \(hasFullscreenWindow)")
            if hasFullscreenWindow {
                AppLogger.shared.info("DEBUG: Fullscreen window detected during check")
            } else {
                AppLogger.shared.info("DEBUG: No fullscreen window detected")
            }
            NotificationCenter.default.post(
                name: NSNotification.Name("FullscreenStateChanged"),
                object: nil,
                userInfo: ["hasFullscreen": hasFullscreenWindow]
            )
        }
    }
    
    private func detectFullscreenWindow() -> Bool {
        // Get the main screen bounds
        guard let mainScreen = NSScreen.main else { 
            AppLogger.shared.debug("DEBUG: No main screen found")
            return false 
        }
        let screenBounds = mainScreen.frame
        AppLogger.shared.debug("DEBUG: Screen bounds: \(screenBounds)")
        
        // Get all on-screen windows
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            AppLogger.shared.debug("DEBUG: Failed to get window list")
            return false
        }
        
        AppLogger.shared.debug("DEBUG: Found \(windowList.count) windows to check")
        
        for windowInfo in windowList {
            // Skip WinDock windows and system windows
            if let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
               let app = NSRunningApplication(processIdentifier: ownerPID) {
                
                // Skip WinDock itself
                if app.bundleIdentifier == Bundle.main.bundleIdentifier {
                    continue
                }
                
                // Skip system apps and non-regular apps
                if app.activationPolicy != .regular {
                    continue
                }
                
                AppLogger.shared.debug("DEBUG: Checking window from app: \(app.localizedName ?? "Unknown")")
            }
            
            // Check window layer - skip non-main windows (docks, menus, etc.)
            guard let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0 else { // Only check main window layer
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
                  alpha > 0.9 else {
                continue
            }
            
            AppLogger.shared.debug("DEBUG: Window bounds: \(bounds), alpha: \(alpha)")
            
            // More strict fullscreen detection - must cover exactly the entire screen
            let tolerance: CGFloat = 2
            let coversWidth = abs(bounds.width - screenBounds.width) <= tolerance
            let coversHeight = abs(bounds.height - screenBounds.height) <= tolerance
            let positionedAtOrigin = abs(bounds.origin.x - screenBounds.origin.x) <= tolerance && 
                                   abs(bounds.origin.y - screenBounds.origin.y) <= tolerance
            
            if coversWidth && coversHeight && positionedAtOrigin {
                // Additional check: get window name to avoid false positives
                if let windowName = windowInfo[kCGWindowName as String] as? String,
                   !windowName.isEmpty {
                    AppLogger.shared.info("Detected fullscreen window: \(windowName)")
                    return true
                } else {
                    AppLogger.shared.debug("DEBUG: Found fullscreen-sized window but no name - might be false positive")
                }
            }
        }
        
        AppLogger.shared.debug("DEBUG: No fullscreen windows detected")
        return false
    }
    
    deinit {
        stopMonitoring()
    }
}
