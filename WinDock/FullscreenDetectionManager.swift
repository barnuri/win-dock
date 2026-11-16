import AppKit
import SwiftUI

class FullscreenDetectionManager: ObservableObject {
    static let shared = FullscreenDetectionManager()
    
    @Published private(set) var hasFullscreenWindow = false
    private var monitoringTimer: Timer?
    private var isRunning = false
    private var startupTime: Date?
    private var monitoringGeneration = 0
    private static let maxDisplayCount: UInt32 = 32
    private static let boundsTolerance: CGFloat = 2
    
    private init() {}
    
    func startMonitoring() {
        guard !isRunning else { return }
        
        isRunning = true
        startupTime = Date()
        monitoringGeneration += 1
        let generation = monitoringGeneration
        
        // Add delay to prevent false positives during startup
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self, self.isRunning, self.monitoringGeneration == generation else { return }
            // Low-frequency safety poll; space/activation notifications below drive prompt updates.
            self.monitoringTimer?.invalidate()
            self.monitoringTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.checkForFullscreenWindows()
            }

            // Run initial check after delay
            self.checkForFullscreenWindows()
        }

        // Listen for app activation and Space changes for immediate, event-driven updates
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

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSWorkspace.activeSpaceDidChangeNotification,
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
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        AppLogger.shared.info("FullscreenDetectionManager stopped monitoring")
    }
    
    @objc private func appDidBecomeActive() {
        // Check immediately when an app becomes active
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.checkForFullscreenWindows()
        }
    }

    @objc private func appDidResignActive() {
        // Check when an app resigns active status
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.checkForFullscreenWindows()
        }
    }

    private func checkForFullscreenWindows() {
        // Skip detection for the first 10 seconds after startup to avoid false positives
        if let startupTime = startupTime, Date().timeIntervalSince(startupTime) < 10.0 {
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let detected = Self.detectFullscreenWindow(displayBounds: Self.activeDisplayBounds())
            DispatchQueue.main.async {
                guard let self = self else { return }
                let previousState = self.hasFullscreenWindow
                self.hasFullscreenWindow = detected
                guard previousState != detected else { return }
                AppLogger.shared.info("Fullscreen state changed: \(detected)")
                NotificationCenter.default.post(
                    name: NSNotification.Name("FullscreenStateChanged"),
                    object: nil,
                    userInfo: ["hasFullscreen": detected]
                )
            }
        }
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplayCount))
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(maxDisplayCount, &displayIDs, &displayCount) == .success else {
            return []
        }
        return displayIDs.prefix(Int(displayCount)).map { CGDisplayBounds($0) }
    }

    static func windowMatchesAnyDisplay(_ windowBounds: CGRect, displayBounds: [CGRect]) -> Bool {
        displayBounds.contains { display in
            abs(windowBounds.width - display.width) <= boundsTolerance &&
                abs(windowBounds.height - display.height) <= boundsTolerance &&
                abs(windowBounds.origin.x - display.origin.x) <= boundsTolerance &&
                abs(windowBounds.origin.y - display.origin.y) <= boundsTolerance
        }
    }

    private static func detectFullscreenWindow(displayBounds: [CGRect]) -> Bool {
        guard !displayBounds.isEmpty else { return false }

        // Get all on-screen windows
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for windowInfo in windowList {
            // Check window layer - skip non-main windows (docks, menus, etc.)
            guard let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0 else {
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

            // Window and display bounds are both in CG global coordinates (top-left origin)
            guard windowMatchesAnyDisplay(bounds, displayBounds: displayBounds),
                  let windowName = windowInfo[kCGWindowName as String] as? String,
                  !windowName.isEmpty else {
                continue
            }

            // NSRunningApplication lookup is an IPC round-trip, so it runs only for candidates.
            if let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
               let app = NSRunningApplication(processIdentifier: ownerPID),
               app.bundleIdentifier == Bundle.main.bundleIdentifier || app.activationPolicy != .regular {
                continue
            }

            AppLogger.shared.info("Detected fullscreen window: \(windowName)")
            return true
        }

        return false
    }
    
    deinit {
        stopMonitoring()
    }
}
