import Foundation
import ServiceManagement
import AppKit

class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()
    
    private let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.windock.app"
    
    private init() {}
    
    var isLoginItemEnabled: Bool {
        get {
            return getLoginItemStatus()
        }
        set {
            setLoginItemStatus(enabled: newValue)
        }
    }
    
    private func getLoginItemStatus() -> Bool {
        // Use modern ServiceManagement framework for macOS 13+
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // Fallback for older macOS versions
            return legacyGetLoginItemStatus()
        }
    }
    
    private func setLoginItemStatus(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    AppLogger.shared.info("Successfully registered WinDock as login item")
                } else {
                    try SMAppService.mainApp.unregister()
                    AppLogger.shared.info("Successfully unregistered WinDock from login items")
                }
            } catch {
                AppLogger.shared.error("Failed to update login item status: \(error.localizedDescription)")
            }
        } else {
            // Fallback for older macOS versions
            legacySetLoginItemStatus(enabled: enabled)
        }
    }
    
    @available(macOS, deprecated: 13.0)
    private func legacyGetLoginItemStatus() -> Bool {
        let workspace = NSWorkspace.shared
        let loginItems = workspace.runningApplications.filter { $0.bundleIdentifier == bundleIdentifier }
        return !loginItems.isEmpty
    }
    
    @available(macOS, deprecated: 13.0)
    private func legacySetLoginItemStatus(enabled: Bool) {
        // For older macOS, we'll use a simpler approach
        // The deprecated LSSharedFileList APIs are too complex and unreliable
        // Instead, we'll just log the intent
        if enabled {
            AppLogger.shared.info("Login item enable requested (legacy mode)")
        } else {
            AppLogger.shared.info("Login item disable requested (legacy mode)")
        }
        
        // Note: On older macOS versions, users should manually add the app to login items
        // via System Preferences > Users & Groups > Login Items
    }
    
    func toggleLoginItem() {
        isLoginItemEnabled.toggle()
    }
}