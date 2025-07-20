import Foundation
import AppKit
import CoreGraphics

class WindowManagerIntegration: ObservableObject {
    static let shared = WindowManagerIntegration()
    
    private var reservedAreas: [CGDirectDisplayID: CGRect] = [:]
    private var dockPosition: DockPosition = .bottom
    
    private init() {
        setupWindowManagement()
    }
    
    private func setupWindowManagement() {
        // Listen for window management events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowMaximize),
            name: NSNotification.Name("WindowWillMaximize"),
            object: nil
        )
        
        // Monitor for window resize events from system
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleSystemWindowEvent),
            name: NSNotification.Name("com.apple.accessibility.api"),
            object: nil
        )
    }
    
    func updateReservation(displayID: CGDirectDisplayID, area: CGRect, position: DockPosition) {
        reservedAreas[displayID] = area
        dockPosition = position
        
        // Broadcast to window managers
        broadcastReservationUpdate()
    }
    
    func removeReservation(displayID: CGDirectDisplayID) {
        reservedAreas.removeValue(forKey: displayID)
        broadcastReservationUpdate()
    }
    
    private func broadcastReservationUpdate() {
        // Method 1: Distributed notification for system-wide communication
        let userInfo: [String: Any] = [
            "reservedAreas": reservedAreas.mapKeys { String($0) },
            "position": dockPosition.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        DistributedNotificationCenter.default().post(
            name: NSNotification.Name("WinDockReservationUpdate"),
            object: "com.windock.app",
            userInfo: userInfo
        )
        
        // Method 2: Create/update shared file for other window managers
        updateSharedConfigFile()
        
        // Method 3: Update accessibility settings
        updateAccessibilityAPI()
    }
    
    private func updateSharedConfigFile() {
        guard let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        
        let configURL = supportURL.appendingPathComponent("WinDock").appendingPathComponent("window-config.json")
        
        do {
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            
            let config: [String: Any] = [
                "version": "1.0",
                "active": !reservedAreas.isEmpty,
                "position": dockPosition.rawValue,
                "reservations": reservedAreas.map { (key, value) in
                    [
                        "displayID": String(key),
                        "area": [
                            "x": value.origin.x,
                            "y": value.origin.y,
                            "width": value.size.width,
                            "height": value.size.height
                        ]
                    ]
                },
                "lastUpdate": Date().timeIntervalSince1970
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
            try jsonData.write(to: configURL)
            
            AppLogger.shared.info("Updated window manager config: \(configURL.path)")
        } catch {
            AppLogger.shared.error("Failed to update window manager config", error: error)
        }
    }
    
    private func updateAccessibilityAPI() {
        // Use Accessibility API to inform system about reserved screen areas
        for (displayID, area) in reservedAreas {
            let key = "WinDockReservation_\(displayID)"
            
            // Store in accessibility preferences (this is a simplified approach)
            let prefs = [
                "area": NSStringFromRect(area),
                "position": dockPosition.rawValue,
                "active": true
            ] as [String: Any]
            
            CFPreferencesSetValue(
                key as CFString,
                prefs as CFPropertyList,
                "com.apple.accessibility" as CFString,
                kCFPreferencesAnyUser,
                kCFPreferencesCurrentHost
            )
        }
        
        CFPreferencesSynchronize(
            "com.apple.accessibility" as CFString,
            kCFPreferencesAnyUser,
            kCFPreferencesCurrentHost
        )
    }
    
    @objc private func handleWindowMaximize(_ notification: Notification) {
        // Handle window maximization to respect dock area
        guard let window = notification.object as? NSWindow else { return }
        
        adjustWindowForDockArea(window)
    }
    
    @objc private func handleSystemWindowEvent(_ notification: Notification) {
        // Handle system-wide window events
        AppLogger.shared.info("System window event received")
    }
    
    private func adjustWindowForDockArea(_ window: NSWindow) {
        guard let screen = window.screen,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let reservedArea = reservedAreas[displayID] else { return }
        
        let screenFrame = screen.frame
        var adjustedFrame = screenFrame
        
        // Adjust the available area based on dock position
        switch dockPosition {
        case .bottom:
            adjustedFrame.size.height -= reservedArea.height
            adjustedFrame.origin.y += reservedArea.height
        case .top:
            adjustedFrame.size.height -= reservedArea.height
        case .left:
            adjustedFrame.origin.x += reservedArea.width
            adjustedFrame.size.width -= reservedArea.width
        case .right:
            adjustedFrame.size.width -= reservedArea.width
        }
        
        // Apply the adjusted frame if the window is being maximized
        if window.isZoomed || window.frame.size == screenFrame.size {
            window.setFrame(adjustedFrame, display: true, animate: true)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }
}

extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            result[transform(key)] = value
        }
        return result
    }
}
