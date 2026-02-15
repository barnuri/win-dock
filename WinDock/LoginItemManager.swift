import Foundation
import ServiceManagement
import AppKit

class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()
    
    @Published var lastError: String?
    @Published var isProcessing: Bool = false
    
    private let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.windock.app"
    private let hasSetDefaultKey = "HasSetDefaultLaunchAtLogin"
    
    private init() {
        // Set default to true on first launch
        if !UserDefaults.standard.bool(forKey: hasSetDefaultKey) {
            UserDefaults.standard.set(true, forKey: hasSetDefaultKey)
            // Enable by default on first launch
            Task {
                await MainActor.run {
                    isLoginItemEnabled = true
                }
            }
            AppLogger.shared.info("Launch at login enabled by default on first launch")
        }
    }
    
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
        // Must be called from main thread since we modify @Published properties
        assert(Thread.isMainThread, "setLoginItemStatus must be called from the main thread")

        lastError = nil
        isProcessing = true

        if #available(macOS 13.0, *) {
            do {
                let service = SMAppService.mainApp

                if enabled {
                    // If already enabled, no need to register again
                    if service.status == .enabled {
                        AppLogger.shared.debug("Login item already enabled")
                        isProcessing = false
                        return
                    }

                    try service.register()
                    AppLogger.shared.info("Successfully registered WinDock as login item")
                    isProcessing = false
                } else {
                    // If already disabled, no need to unregister
                    if service.status == .notRegistered {
                        AppLogger.shared.debug("Login item already disabled")
                        isProcessing = false
                        return
                    }

                    // Note: unregister is async on macOS 13+
                    Task {
                        do {
                            try await service.unregister()
                            await MainActor.run {
                                self.isProcessing = false
                            }
                            AppLogger.shared.info("Successfully unregistered WinDock from login items")
                        } catch {
                            await MainActor.run {
                                self.lastError = "Failed to unregister: \(error.localizedDescription)"
                                self.isProcessing = false
                            }
                            AppLogger.shared.error("Failed to unregister from login items: \(error.localizedDescription)")
                        }
                    }
                }
            } catch {
                lastError = "Failed to update login item: \(error.localizedDescription)"
                isProcessing = false
                AppLogger.shared.error("Failed to update login item status: \(error.localizedDescription)")
            }
        } else {
            // Fallback for older macOS versions
            legacySetLoginItemStatus(enabled: enabled)
            isProcessing = false
        }
    }
    
    /// Get status message for display
    var statusMessage: String {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            switch service.status {
            case .enabled:
                return "Enabled"
            case .notRegistered:
                return "Disabled"
            case .requiresApproval:
                return "Requires approval in System Settings"
            case .notFound:
                return "Service not found"
            @unknown default:
                return "Unknown status"
            }
        } else {
            return "Not supported on this macOS version"
        }
    }
    
    /// Check if approval is required
    var requiresApproval: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .requiresApproval
        }
        return false
    }
    
    /// Open System Settings to Login Items
    func openSystemSettings() {
        if #available(macOS 13.0, *) {
            let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
            NSWorkspace.shared.open(url)
            AppLogger.shared.info("Opened System Settings for login items")
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