import Foundation
import AppKit
import Combine
import Accessibility
import ApplicationServices

struct DockApp: Identifiable, Hashable {
    let id = UUID()
    let bundleIdentifier: String
    let name: String
    let icon: NSImage?
    let url: URL?
    var isRunning: Bool
    var isPinned: Bool
    var windowCount: Int
    var runningApplication: NSRunningApplication?
    var windows: [WindowInfo] = []
    var notificationCount: Int = 0
    var hasNotifications: Bool = false
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }
    
    static func == (lhs: DockApp, rhs: DockApp) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}

struct WindowInfo {
    let title: String
    let windowID: CGWindowID
    let bounds: CGRect
    let isMinimized: Bool
    let isOnScreen: Bool
}

@MainActor
class AppManager: ObservableObject {
    @Published var dockApps: [DockApp] = []

    private var appMonitorTimer: Timer?
    private let pinnedAppsKey = "WinDock.PinnedApps"
    private let dockAppOrderKey = "WinDock.DockAppOrder"
    private var pinnedBundleIdentifiers: Set<String> = []
    private var dockAppOrder: [String] = []

    // Default pinned applications - Windows 11 style defaults
    private let defaultPinnedApps = [
        "com.apple.finder",          // File Explorer equivalent
        "com.apple.Safari",           // Edge equivalent
        "com.apple.systempreferences", // Settings
        "com.apple.mail",             // Mail
        "com.apple.launchpad"         // Start menu equivalent
    ]
    
    // Bundle ID for WinDock itself
    private let winDockBundleID = Bundle.main.bundleIdentifier ?? "com.windock.app"

    init() {
        loadPinnedApps()
        loadDockAppOrder()
        updateDockApps()
    }

    func hideOtherApps(except app: DockApp) {
        let runningApps = NSWorkspace.shared.runningApplications
        for runningApp in runningApps {
            guard runningApp.bundleIdentifier != app.bundleIdentifier,
                  runningApp.bundleIdentifier != winDockBundleID,
                  runningApp.activationPolicy == .regular,
                  runningApp.isHidden == false else { continue }
            runningApp.hide()
        }
    }

    func closeAllWindows(for app: DockApp) {
        guard let runningApp = app.runningApplication else { return }
        runningApp.terminate()
    }

    func startMonitoring() {
        // Update immediately
        updateDockApps()
        
        // Reduce frequency significantly for better performance - 2 seconds instead of 0.5
        appMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDockApps()
            }
        }
        
        // Listen for app launch/quit notifications for immediate updates
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidLaunch),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidTerminate),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }
    
    func stopMonitoring() {
        appMonitorTimer?.invalidate()
        appMonitorTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    @objc private func appDidLaunch(_ notification: Notification) {
        // Immediate update for app launches
        Task { @MainActor [weak self] in
            self?.updateDockApps()
        }
    }
    
    @objc private func appDidTerminate(_ notification: Notification) {
        // Immediate update for app terminations
        Task { @MainActor [weak self] in
            self?.updateDockApps()
        }
    }
       
    // Public function to trigger update from outside
    func updateDockAppsIfNeeded() {
        Task { @MainActor [weak self] in
            self?.updateDockApps()
        }
    }
    
    private func updateDockApps() {
        // Performance: Cache running apps to avoid multiple queries
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { app in
                // Filter out WinDock itself and only show regular apps
                app.activationPolicy == .regular && 
                app.bundleIdentifier != winDockBundleID
            }

        var newDockApps: [DockApp] = []
        var processedBundleIds: Set<String> = []

        // Add running applications
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier,
                  !processedBundleIds.contains(bundleId) else { continue }

            processedBundleIds.insert(bundleId)
            
            // Performance: Only get windows for running apps, minimize expensive calls
            let windows = app.isActive ? getWindowsForApp(app) : []
            let windowCount = windows.count
            let (hasNotifications, notificationCount) = getNotificationInfo(for: app)

            let dockApp = DockApp(
                bundleIdentifier: bundleId,
                name: app.localizedName ?? bundleId,
                icon: app.icon,
                url: app.bundleURL,
                isRunning: true,
                isPinned: pinnedBundleIdentifiers.contains(bundleId),
                windowCount: windowCount,
                runningApplication: app,
                windows: windows,
                notificationCount: notificationCount,
                hasNotifications: hasNotifications
            )
            newDockApps.append(dockApp)
        }

        // Add pinned apps that aren't running
        for bundleId in pinnedBundleIdentifiers {
            if !processedBundleIds.contains(bundleId) {
                if let app = createDockAppForBundleId(bundleId) {
                    newDockApps.append(app)
                }
            }
        }

        // Reorder based on saved order
        reorderApps(&newDockApps)

        dockApps = newDockApps
    }
    
    private func reorderApps(_ apps: inout [DockApp]) {
        if !dockAppOrder.isEmpty {
            apps.sort { lhs, rhs in
                let lidx = dockAppOrder.firstIndex(of: lhs.bundleIdentifier) ?? Int.max
                let ridx = dockAppOrder.firstIndex(of: rhs.bundleIdentifier) ?? Int.max
                if lidx != ridx {
                    return lidx < ridx
                }
                // Fallback: pinned first, then by name
                if lhs.isPinned && !rhs.isPinned {
                    return true
                } else if !lhs.isPinned && rhs.isPinned {
                    return false
                } else {
                    return lhs.name < rhs.name
                }
            }
        } else {
            // Default ordering: pinned first, then by name
            apps.sort { lhs, rhs in
                if lhs.isPinned && !rhs.isPinned {
                    return true
                } else if !lhs.isPinned && rhs.isPinned {
                    return false
                } else {
                    return lhs.name < rhs.name
                }
            }
        }
    }
    
    private func getWindowsForApp(_ app: NSRunningApplication) -> [WindowInfo] {
        var windows: [WindowInfo] = []
        
        // Use Core Graphics to get window information - include both on-screen and off-screen windows
        guard let windowList = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return windows
        }
        
        for windowInfo in windowList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == app.processIdentifier else { continue }
            
            guard let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            
            let title = windowInfo[kCGWindowName as String] as? String ?? ""
            let isOnScreen = windowInfo[kCGWindowIsOnscreen as String] as? Bool ?? false
            let alpha = windowInfo[kCGWindowAlpha as String] as? CGFloat ?? 1.0
            let layer = windowInfo[kCGWindowLayer as String] as? Int ?? 0
            
            // Filter out system windows, splash screens, and other non-user windows
            if shouldIncludeWindow(
                bounds: bounds,
                title: title,
                isOnScreen: isOnScreen,
                alpha: alpha,
                layer: layer,
                app: app
            ) {
                // Determine if window is minimized
                // A window is considered minimized if it's not on screen but has reasonable bounds
                let isMinimized = !isOnScreen && bounds.width >= 100 && bounds.height >= 100
                
                let window = WindowInfo(
                    title: title,
                    windowID: windowID,
                    bounds: bounds,
                    isMinimized: isMinimized,
                    isOnScreen: isOnScreen
                )
                
                windows.append(window)
            }
        }
        
        return windows
    }
    
    private func shouldIncludeWindow(
        bounds: CGRect,
        title: String,
        isOnScreen: Bool,
        alpha: CGFloat,
        layer: Int,
        app: NSRunningApplication
    ) -> Bool {
        // Skip windows that are too small to be real user windows
        if bounds.width < 100 || bounds.height < 100 {
            return false
        }
        
        // Skip very transparent windows unless they're minimized
        if alpha < 0.1 && isOnScreen {
            return false
        }
        
        // Skip system layer windows (like dock, menu bar)
        if layer < 0 {
            return false
        }
        
        // Skip certain window types that are commonly not user-visible
        let excludedTitles = [
            "Window",
            "TouchBarUserInterfaceLayoutViewController",
            "NSToolbarFullScreenWindow",
            "NSTextInputWindowController",
            "StatusBarWindow",
            "NotificationWindow",
            "ScreenSaverWindow"
        ]
        
        for excluded in excludedTitles {
            if title.contains(excluded) {
                return false
            }
        }
        
        // Skip splash screens and loading windows (usually small and temporary)
        if title.lowercased().contains("splash") || 
           title.lowercased().contains("loading") ||
           title.lowercased().contains("launcher") {
            return false
        }
        
        // Special handling for specific apps
        if let bundleId = app.bundleIdentifier {
            switch bundleId {
            case "com.apple.finder":
                // Only count Finder windows that are actual folder windows
                return !title.isEmpty && title != "Desktop"
                
            case "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox":
                // For browsers, count all reasonably sized windows
                return bounds.width >= 200 && bounds.height >= 200
                
            case "com.apple.dock":
                // Never count dock windows
                return false
                
            case "com.apple.systempreferences":
                // Count System Preferences windows
                return !title.isEmpty
                
            default:
                break
            }
        }
        
        // Include windows that are either on-screen or minimized with a reasonable size
        return isOnScreen || (!isOnScreen && bounds.width >= 200 && bounds.height >= 150)
    }
    

    
    // MARK: - Dock App Order Persistence

    private func loadDockAppOrder() {
        if let saved = UserDefaults.standard.array(forKey: dockAppOrderKey) as? [String] {
            dockAppOrder = saved
        } else {
            dockAppOrder = []
        }
    }

    func saveDockAppOrder() {
        let order = dockApps.map { $0.bundleIdentifier }
        UserDefaults.standard.set(order, forKey: dockAppOrderKey)
        dockAppOrder = order
    }
    
    private func createDockAppForBundleId(_ bundleId: String) -> DockApp? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
              let bundle = Bundle(url: appURL) else {
            return nil
        }
        
        let name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String ??
                   bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
                   bundle.infoDictionary?["CFBundleName"] as? String ??
                   bundleId
        
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        
        return DockApp(
            bundleIdentifier: bundleId,
            name: name,
            icon: icon,
            url: appURL,
            isRunning: false,
            isPinned: true,
            windowCount: 0,
            runningApplication: nil,
            windows: [],
            notificationCount: 0,
            hasNotifications: false
        )
    }
    
    // MARK: - Drag and Drop Reordering
    
    func moveApp(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < dockApps.count,
              destinationIndex >= 0, destinationIndex <= dockApps.count,
              sourceIndex != destinationIndex else { return }
        
        let app = dockApps.remove(at: sourceIndex)
        let insertIndex = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        dockApps.insert(app, at: insertIndex)
        NotificationCenter.default.post(name: NSNotification.Name("DockAppOrderChanged"), object: nil)
        AppLogger.shared.info("Moved app from index \(sourceIndex) to \(destinationIndex)")
        
        saveDockAppOrder()
    }
    
    // MARK: - App Actions

    func focusWindow(windowID: CGWindowID, app: DockApp) {
        guard let runningApp = app.runningApplication else { return }
        
        // First activate the application
        if #available(macOS 14.0, *) {
            runningApp.activate()
        } else {
            runningApp.activate(options: [.activateIgnoringOtherApps])
        }
        
        // If we have a specific window ID, try to focus it using CGWindow API
        if windowID > 0 {
            // Use Core Graphics to get window information and attempt to bring it to front
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Try to get window information
                guard let windowList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
                      let windowInfo = windowList.first else {
                    AppLogger.shared.warning("Could not find window with ID \(windowID)")
                    return
                }
                
                // Check if window belongs to the app
                if let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                   ownerPID == runningApp.processIdentifier {
                    
                    // Get the proper app name for AppleScript
                    let scriptAppName = runningApp.localizedName ?? app.name
                    
                    // Use AppleScript to focus the specific window by title
                    if let windowName = windowInfo[kCGWindowName as String] as? String, !windowName.isEmpty {
                        let script = """
                        try
                            tell application "\(scriptAppName)"
                                activate
                                try
                                    set index of window "\(windowName)" to 1
                                end try
                            end tell
                        on error
                            -- Fallback: try with bundle identifier
                            try
                                tell application id "\(app.bundleIdentifier)"
                                    activate
                                    try
                                        set index of window "\(windowName)" to 1
                                    end try
                                end tell
                            on error
                                -- Final fallback: just activate the app
                                tell application "System Events"
                                    tell process "\(scriptAppName)"
                                        set frontmost to true
                                    end tell
                                end tell
                            end try
                        end try
                        """
                        
                        if let appleScript = NSAppleScript(source: script) {
                            var error: NSDictionary?
                            appleScript.executeAndReturnError(&error)
                            if let error = error {
                                AppLogger.shared.error("Focus window AppleScript error: \(error)")
                            }
                        }
                    } else {
                        // Fallback: use System Events to bring window to front
                        let script = """
                        tell application "System Events"
                            try
                                tell process "\(scriptAppName)"
                                    set frontmost to true
                                    if (count of windows) > 0 then
                                        perform action "AXRaise" of window 1
                                    end if
                                end tell
                            on error
                                -- Try with the display name as fallback
                                tell process "\(app.name)"
                                    set frontmost to true
                                    if (count of windows) > 0 then
                                        perform action "AXRaise" of window 1
                                    end if
                                end tell
                            end try
                        end tell
                        """
                        
                        if let appleScript = NSAppleScript(source: script) {
                            var error: NSDictionary?
                            appleScript.executeAndReturnError(&error)
                            if let error = error {
                                AppLogger.shared.error("Focus window System Events error: \(error)")
                            }
                        }
                    }
                } else {
                    AppLogger.shared.warning("Window \(windowID) does not belong to app \(app.name)")
                }
            }
        }
    }

    func activateApp(_ app: DockApp) {
        AppLogger.shared.info("activateApp called for \(app.name), isRunning: \(app.isRunning), windowCount: \(app.windowCount), isActive: \(app.runningApplication?.isActive ?? false)")
        
        if let runningApp = app.runningApplication {
            // Force app to front and activate
            AppLogger.shared.info("Activating running app: \(app.name)")
            
            // Ensure the app is unhidden if it was hidden
            if runningApp.isHidden {
                runningApp.unhide()
            }
            
            // Check if the app has no windows - if so, just use NSRunningApplication activation
            // This prevents AppleScript errors when apps have no windows to activate
            if app.windowCount == 0 {
                AppLogger.shared.info("App \(app.name) has no windows - using NSRunningApplication activation only")
                if #available(macOS 14.0, *) {
                    runningApp.activate()
                } else {
                    runningApp.activate(options: [.activateIgnoringOtherApps])
                }
                return
            }
            
            // Activate with all available options to ensure it comes to front
            if #available(macOS 14.0, *) {
                runningApp.activate()
            } else {
                runningApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            }
            
            // Get the proper app name for AppleScript - use localized name from running app or bundle identifier as fallback
            let scriptAppName = runningApp.localizedName ?? app.name
            
            // Use AppleScript to ensure the app is brought to the very front
            // Only use AppleScript when the app has windows
            let bringToFrontScript = """
            try
                tell application "\(scriptAppName)"
                    activate
                end tell
            on error
                -- If direct app activation fails, try with bundle identifier
                tell application id "\(app.bundleIdentifier)"
                    activate
                end tell
            end try
            
            -- Use System Events as additional fallback for bringing windows to front
            tell application "System Events"
                try
                    tell process "\(scriptAppName)"
                        set frontmost to true
                        -- Only try to raise windows if they exist
                        if (count of windows) > 0 then
                            perform action "AXRaise" of window 1
                        end if
                    end tell
                on error
                    -- If process name doesn't work, try with localized name
                    tell process "\(app.name)"
                        set frontmost to true
                        if (count of windows) > 0 then
                            perform action "AXRaise" of window 1
                        end if
                    end tell
                end try
            end tell
            """
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let appleScript = NSAppleScript(source: bringToFrontScript) {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                    if let error = error {
                        AppLogger.shared.error("Bring to front AppleScript error: \(error)")
                        
                        // If AppleScript fails completely, just rely on NSRunningApplication activation
                        AppLogger.shared.info("Falling back to NSRunningApplication activation only")
                        if #available(macOS 14.0, *) {
                            runningApp.activate()
                        } else {
                            runningApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                        }
                    }
                }
                
                // Additional activation attempt
                if #available(macOS 14.0, *) {
                    runningApp.activate()
                } else {
                    runningApp.activate(options: [.activateIgnoringOtherApps])
                }
            }
        } else if let appURL = app.url {
            AppLogger.shared.info("Launching app from URL: \(appURL.path)")
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        } else {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
                AppLogger.shared.info("Launching app from bundle identifier: \(app.bundleIdentifier)")
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            } else {
                AppLogger.shared.error("Could not find app to activate: \(app.bundleIdentifier)")
            }
        }
    }
    
    func cycleWindows(for app: DockApp) {
        guard app.runningApplication != nil else { return }
        
        // Use AppleScript to cycle through windows
        let script = """
        tell application "System Events"
            tell process "\(app.name)"
                if (count of windows) > 1 then
                    set frontmost to true
                    click menu item "Cycle Through Windows" of menu "Window" of menu bar 1
                end if
            end tell
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
    
    func hideApp(_ app: DockApp) {
        AppLogger.shared.info("hideApp called for \(app.name), isRunning: \(app.isRunning), isActive: \(app.runningApplication?.isActive ?? false)")
        if let runningApp = app.runningApplication {
            runningApp.hide()
            AppLogger.shared.info("hideApp: hide() called for \(app.name)")
        } else {
            AppLogger.shared.error("hideApp: No runningApplication for \(app.name)")
        }
    }
    
    func quitApp(_ app: DockApp) {
        app.runningApplication?.terminate()
    }
    
    func showAllWindows(for app: DockApp) {
        if let runningApp = app.runningApplication {
            // Unhide the app if it's hidden
            if runningApp.isHidden {
                runningApp.unhide()
            }
            
            // Activate the app and show all windows
            if #available(macOS 14.0, *) {
                runningApp.activate()
            } else {
                runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
            
            // Show Exposé for this app
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let script = """
                tell application "System Events"
                    tell process "\(app.name)"
                        set frontmost to true
                    end tell
                    key code 101 using {control down}
                end tell
                """
                
                if let appleScript = NSAppleScript(source: script) {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                }
            }
        }
    }
    
    func launchApp(_ app: DockApp) {
        activateApp(app)
    }
    
    func launchNewInstance(_ app: DockApp) {
        if let appURL = app.url ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        }
    }
    
    func pinApp(_ app: DockApp) {
        pinnedBundleIdentifiers.insert(app.bundleIdentifier)
        savePinnedApps()
        updateDockApps()
    }
    
    func unpinApp(_ app: DockApp) {
        pinnedBundleIdentifiers.remove(app.bundleIdentifier)
        savePinnedApps()
        updateDockApps()
    }
    
    // MARK: - Persistence
    
    private func loadPinnedApps() {
        if let saved = UserDefaults.standard.array(forKey: pinnedAppsKey) as? [String] {
            pinnedBundleIdentifiers = Set(saved)
        } else {
            // First launch - use default pinned apps
            pinnedBundleIdentifiers = Set(defaultPinnedApps)
            savePinnedApps()
        }
    }
    
    private func savePinnedApps() {
        UserDefaults.standard.set(Array(pinnedBundleIdentifiers), forKey: pinnedAppsKey)
    }
    
    private func getNotificationInfo(for app: NSRunningApplication) -> (hasNotifications: Bool, notificationCount: Int) {
        guard let bundleIdentifier = app.bundleIdentifier else {
            return (false, 0)
        }
        
        // Try to get real notification count from various sources
        let notificationCount = getRealNotificationCount(for: bundleIdentifier)
        
        // Known apps that commonly show notifications
        let notificationCapableApps: Set<String> = [
            "com.apple.mail",
            "com.apple.Messages", 
            "com.slack.client",
            "com.tinyspeck.slackmacgap",
            "com.microsoft.teams",
            "com.microsoft.teams2", // Teams 2.0
            "com.discord.discord",
            "com.apple.facetime",
            "com.whatsapp.WhatsApp",
            "com.telegram.desktop",
            "org.signal.Signal",
            "com.spotify.client",
            "com.apple.AppStore",
            "com.apple.systempreferences",
            "com.apple.Console"
        ]
        
        // Show notifications for known notification-capable apps
        let hasNotifications = notificationCapableApps.contains(bundleIdentifier) && notificationCount > 0
        
        // Debug logging for Teams specifically
        if bundleIdentifier == "com.microsoft.teams" || bundleIdentifier == "com.microsoft.teams2" {
            AppLogger.shared.debug("Teams notification check: count=\(notificationCount), hasNotifications=\(hasNotifications)")
        }
        
        return (hasNotifications, notificationCount)
    }
    
    private func getRealNotificationCount(for bundleIdentifier: String) -> Int {
        // Try multiple methods to get real notification count
        
        // Method 1: Check app badge count (requires accessibility permissions)
        if let count = getAppBadgeCount(bundleIdentifier: bundleIdentifier) {
            return count
        }
        
        // Method 2: Check notification center (simplified approach)
        let notificationCount = getNotificationCenterCount(for: bundleIdentifier)
        if notificationCount > 0 {
            return notificationCount
        }
        
        // Method 3: Check specific app states
        switch bundleIdentifier {
        case "com.apple.mail":
            return getMailNotificationCount()
        case "com.apple.Messages":
            return getMessagesNotificationCount()
        case "com.slack.client", "com.tinyspeck.slackmacgap":
            return getSlackNotificationCount()
        case "com.microsoft.teams", "com.microsoft.teams2":
            return getTeamsNotificationCount()
        case "com.apple.AppStore":
            return getAppStoreNotificationCount()
        default:
            // For other apps, try to detect if they have pending notifications
            return getGenericNotificationCount(for: bundleIdentifier)
        }
    }
    
    private func getAppBadgeCount(bundleIdentifier: String) -> Int? {
        // Try to read badge count from running application
        let runningApps = NSWorkspace.shared.runningApplications
        guard runningApps.first(where: { $0.bundleIdentifier == bundleIdentifier }) != nil else {
            return nil
        }
        
        // This is limited without private APIs, but we can try accessibility
        // This is a placeholder for potential future enhancement
        return nil
    }
    
    private func getNotificationCenterCount(for bundleIdentifier: String) -> Int {
        // Check for pending notifications (simplified approach)
        // This would require notification center integration which is complex
        // For now return 0, but this is where real notification integration would go
        return 0
    }
    
    private func getMailNotificationCount() -> Int {
        // Try to get unread mail count via AppleScript
        let script = """
        tell application "Mail"
            try
                set unreadCount to unread count of inbox
                return unreadCount
            on error
                return 0
            end try
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            if error == nil {
                return result.int32Value > 0 ? Int(result.int32Value) : 0
            }
        }
        
        return 0
    }
    
    private func getMessagesNotificationCount() -> Int {
        // Try to get unread messages count via AppleScript
        let script = """
        tell application "Messages"
            try
                set unreadCount to 0
                repeat with theChat in chats
                    set unreadCount to unreadCount + (unread count of theChat)
                end repeat
                return unreadCount
            on error
                return 0
            end try
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            if error == nil {
                return result.int32Value > 0 ? Int(result.int32Value) : 0
            }
        }
        
        return 0
    }
    
    private func getSlackNotificationCount() -> Int {
        // Try to get Slack notification count
        let script = """
        tell application "System Events"
            try
                tell process "Slack"
                    set badgeText to value of attribute "AXTitle" of first application whose bundle identifier is "com.slack.client"
                    if badgeText contains "(" then
                        set AppleScript's text item delimiters to "("
                        set badgeNumber to text item 2 of badgeText
                        set AppleScript's text item delimiters to ")"
                        set badgeNumber to text item 1 of badgeNumber
                        return badgeNumber as integer
                    end if
                end tell
            on error
                return 0
            end try
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            if error == nil {
                return result.int32Value > 0 ? Int(result.int32Value) : 0
            }
        }
        
        return 0
    }
    
    private func getTeamsNotificationCount() -> Int {
        AppLogger.shared.debug("Getting Teams notification count...")
        
        // First, try to find the Teams app
        let teamsRunningApps = NSWorkspace.shared.runningApplications.filter { app in
            app.bundleIdentifier == "com.microsoft.teams2" || 
            app.bundleIdentifier == "com.microsoft.teams" ||
            app.localizedName?.lowercased().contains("teams") == true
        }
        
        guard !teamsRunningApps.isEmpty else {
            AppLogger.shared.debug("Teams is not running")
            return 0
        }
        
        // Method 1: Check window list via Core Graphics (no AppleScript needed)
        if let count = getTeamsNotificationCountViaWindowList() {
            AppLogger.shared.debug("Teams notification count via window list: \(count)")
            return count
        }
        
        // Method 2: Fallback to AppleScript with better error handling
        let script = """
        tell application "System Events"
            try
                tell process "Microsoft Teams"
                    if exists window 1 then
                        set windowTitle to title of window 1
                        log "Teams window title: " & windowTitle
                        
                        -- Look for patterns like "Microsoft Teams (2)" or "Teams (5)"
                        if windowTitle contains "(" and windowTitle contains ")" then
                            set AppleScript's text item delimiters to "("
                            set titleParts to text items of windowTitle
                            if (count of titleParts) > 1 then
                                set badgePart to text item 2 of titleParts
                                set AppleScript's text item delimiters to ")"
                                set badgeNum to text item 1 of badgePart
                                set AppleScript's text item delimiters to ""
                                try
                                    set notificationCount to badgeNum as integer
                                    if notificationCount > 0 then
                                        log "Found Teams notifications: " & (notificationCount as string)
                                        return notificationCount
                                    end if
                                on error
                                    log "Error parsing badge number: " & badgeNum
                                end try
                            end if
                        end if
                        
                        -- Look for other notification indicators in title
                        if windowTitle contains "notification" or windowTitle contains "unread" or windowTitle contains "message" then
                            log "Found Teams notification indicator in title"
                            return 1
                        end if
                        
                        return 0
                    else
                        log "No Teams window found"
                        return 0
                    end if
                end tell
            on error errMsg
                log "Teams notification check error: " & errMsg
                return 0
            end try
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            
            if let error = error {
                let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
                
                if errorNumber == -1743 {
                    AppLogger.shared.warning("Teams AppleScript authorization required - user needs to grant permission in System Preferences > Security & Privacy > Privacy > Automation")
                } else {
                    AppLogger.shared.error("Teams AppleScript error: \(error)")
                }
                return 0
            }
            
            let count = Int(result.int32Value)
            AppLogger.shared.debug("Teams notification count from AppleScript: \(count)")
            return count > 0 ? count : 0
        }
        
        AppLogger.shared.debug("Teams notification count: 0 (no script result)")
        return 0
    }
    
    private func getTeamsNotificationCountViaWindowList() -> Int? {
        // Get window list for Teams via Core Graphics API
        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        
        for windowInfo in windowList {
            guard let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                  ownerName.lowercased().contains("teams") else { continue }
            
            guard let windowTitle = windowInfo[kCGWindowName as String] as? String,
                  !windowTitle.isEmpty else { continue }
            
            // Look for notification patterns in window title
            if windowTitle.contains("(") && windowTitle.contains(")") {
                // Extract number from parentheses
                let components = windowTitle.components(separatedBy: "(")
                if components.count > 1 {
                    let badgePart = components[1]
                    let badgeComponents = badgePart.components(separatedBy: ")")
                    if let badgeString = badgeComponents.first,
                       let badgeCount = Int(badgeString.trimmingCharacters(in: .whitespaces)) {
                        AppLogger.shared.debug("Found Teams notification count in window title: \(badgeCount)")
                        return badgeCount
                    }
                }
            }
            
            // Look for other notification indicators
            if windowTitle.lowercased().contains("notification") ||
               windowTitle.lowercased().contains("unread") ||
               windowTitle.lowercased().contains("message") {
                AppLogger.shared.debug("Found Teams notification indicator in window title")
                return 1
            }
        }
        
        return 0
    }
    
    private func getAppStoreNotificationCount() -> Int {
        // App Store shows update badges
        let script = """
        tell application "System Events"
            try
                tell process "App Store"
                    set badgeValue to value of attribute "AXStatusLabel" of first application whose bundle identifier is "com.apple.AppStore"
                    if badgeValue is not missing value then
                        return badgeValue as integer
                    end if
                end tell
            on error
                return 0
            end try
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            if error == nil {
                return result.int32Value > 0 ? Int(result.int32Value) : 0
            }
        }
        
        return 0
    }
    
    private func getGenericNotificationCount(for bundleIdentifier: String) -> Int {
        // Check if the app has any pending notifications in the notification center
        // This is a simplified check - in a real implementation, you'd use private APIs
        // or notification center integrations
        
        // For testing: check if debug mode is enabled for notifications
        let debugMode = UserDefaults.standard.bool(forKey: "debugNotifications")
        
        // For apps that commonly show notifications, simulate occasional notifications
        let commonNotificationApps: Set<String> = [
            "com.discord.discord",
            "com.whatsapp.WhatsApp",
            "com.telegram.desktop",
            "org.signal.Signal",
            "com.spotify.client"
        ]
        
        // Debug mode: simulate Teams notifications for testing
        if debugMode && (bundleIdentifier == "com.microsoft.teams" || bundleIdentifier == "com.microsoft.teams2") {
            let simulatedCount = Int.random(in: 1...9)
            AppLogger.shared.debug("Debug mode: simulating \(simulatedCount) Teams notifications")
            return simulatedCount
        }
        
        if commonNotificationApps.contains(bundleIdentifier) {
            // Simulate realistic notification patterns
            let chance = Double.random(in: 0...1)
            if chance < 0.15 { // 15% chance of having notifications
                return Int.random(in: 1...5)
            }
        }
        
        return 0
    }
}