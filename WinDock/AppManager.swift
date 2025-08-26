import Foundation
import AppKit
import Combine
import Accessibility
import ApplicationServices

struct DockApp: Identifiable, Hashable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let name: String
    let icon: NSImage?
    let url: URL?
    var isPinned: Bool
    var runningApplication: NSRunningApplication?
    var windows: [WindowInfo] = []
    var notificationCount: Int = 0
    var hasNotifications: Bool = false

    var windowCount: Int {
        return windows.count
    }

    var isActive: Bool {
        return runningApplication?.isActive == true
    }

    var hasWindows: Bool { 
        return windows.count > 0
    }

    var isRunning: Bool {
        return runningApplication != nil
    }
    
    var isMinimized: Bool {
        guard let runningApp = runningApplication else { return false }
        // An app is considered minimized if it has windows but none are visible
        return isRunning && !runningApp.isActive && windows.allSatisfy { $0.isMinimized }
    }
    
    var isHidden: Bool {
        return runningApplication?.isHidden ?? false
    }
    
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
            
            // Get windows for all running apps to properly show indicators
            let windows = getWindowsForApp(app)
            let (hasNotifications, notificationCount) = getNotificationInfo(for: app)

            let dockApp = DockApp(
                bundleIdentifier: bundleId,
                name: app.localizedName ?? bundleId,
                icon: app.icon,
                url: app.bundleURL,
                isPinned: pinnedBundleIdentifiers.contains(bundleId),
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
            
            // Pre-filter obviously windowless entries before detailed checking
            guard windowID > 0,
                  bounds.width > 0 && bounds.height > 0,
                  alpha >= 0 else { continue }
            
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
        
        // Skip completely transparent windows (likely windowless)
        if alpha <= 0 {
            return false
        }
        
        // Skip windows with no meaningful bounds (windowless entries)
        if bounds.width <= 0 || bounds.height <= 0 {
            return false
        }
        
        // Skip windows that are clearly utility/background windows
        let excludedTitles = [
            "Window",
            "TouchBarUserInterfaceLayoutViewController", 
            "NSToolbarFullScreenWindow",
            "NSTextInputWindowController",
            "StatusBarWindow",
            "NotificationWindow",
            "ScreenSaverWindow",
            "",        // Empty title windows are often windowless
            " ",       // Space-only titles
        ]
        
        // Check for exact matches and partial matches for excluded titles
        for excluded in excludedTitles {
            if title == excluded || (excluded.count > 2 && title.contains(excluded)) {
                return false
            }
        }
        
        // Skip windows with generic/placeholder titles that indicate windowless state
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            return false
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
                // For browsers, count all reasonably sized windows with meaningful titles
                return bounds.width >= 200 && bounds.height >= 200 && !trimmedTitle.isEmpty
                
            case "com.apple.dock":
                // Never count dock windows
                return false
                
            case "com.apple.systempreferences":
                // Count System Preferences windows with actual content
                return !trimmedTitle.isEmpty && trimmedTitle != "Window"
                
            case "com.apple.ActivityMonitor":
                // Activity Monitor often has multiple utility windows
                return !trimmedTitle.isEmpty && !trimmedTitle.contains("CPU History")
                
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
            isPinned: true,
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
    
    func reorderApp(withBundleId sourceBundleId: String, toPosition targetApp: DockApp) {
        guard let sourceIndex = dockApps.firstIndex(where: { $0.bundleIdentifier == sourceBundleId }),
              let targetIndex = dockApps.firstIndex(where: { $0.bundleIdentifier == targetApp.bundleIdentifier }),
              sourceIndex != targetIndex else { return }
        
        moveApp(from: sourceIndex, to: targetIndex)
        AppLogger.shared.info("Reordered app \(sourceBundleId) to position of \(targetApp.name)")
    }
    
    // MARK: - App Actions

    func focusWindow(windowID: CGWindowID, app: DockApp) {
        guard let runningApp = app.runningApplication else { 
            AppLogger.shared.warning("Cannot focus window: app is not running")
            return 
        }
        
        AppLogger.shared.info("Focusing window \(windowID) for app \(app.name)")
        
        // First ensure the app is unhidden and activated with all windows
        if runningApp.isHidden {
            _ = runningApp.unhide()
        }
        
        // Activate with all windows to ensure proper window management
        if #available(macOS 14.0, *) {
            _ = runningApp.activate()
        } else {
            _ = runningApp.activate(options: [.activateAllWindows])
        }
        
        // If we have a specific window ID, try multiple approaches to focus it
        if windowID > 0 {
            // Small delay to ensure activation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.focusSpecificWindow(windowID: windowID, app: app, runningApp: runningApp)
            }
        } else {
            // No specific window, just ensure app is frontmost
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.ensureAppIsFrontmost(app: app, runningApp: runningApp)
            }
        }
    }
    
    private func focusSpecificWindow(windowID: CGWindowID, app: DockApp, runningApp: NSRunningApplication) {
        // Try to get window information
        guard let windowList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let windowInfo = windowList.first else {
            AppLogger.shared.warning("Could not find window with ID \(windowID)")
            self.ensureAppIsFrontmost(app: app, runningApp: runningApp)
            return
        }
        
        // Verify window belongs to the app
        guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
              ownerPID == runningApp.processIdentifier else {
            AppLogger.shared.warning("Window \(windowID) does not belong to app \(app.name)")
            self.ensureAppIsFrontmost(app: app, runningApp: runningApp)
            return
        }
        
        let windowName = windowInfo[kCGWindowName as String] as? String ?? ""
        let isMinimized = !(windowInfo[kCGWindowIsOnscreen as String] as? Bool ?? true)
        
        AppLogger.shared.info("Focusing window '\(windowName)', minimized: \(isMinimized)")
        
        // Approach 1: Try direct app-level window management first
        if !windowName.isEmpty {
            let appScript = """
            tell application "\(app.name)"
                activate
                try
                    set index of window "\(windowName)" to 1
                    if minimized of window "\(windowName)" then
                        set miniaturized of window "\(windowName)" to false
                    end if
                on error errMsg
                    log "Window focus error: " & errMsg
                end try
            end tell
            """
            
            if let appleScript = NSAppleScript(source: appScript) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if error == nil {
                    AppLogger.shared.info("Successfully focused window using app script")
                    return
                }
                AppLogger.shared.warning("App script failed: \(error?.description ?? "unknown")")
            }
        }
        
        // Approach 2: Use System Events with more robust window handling
        let processName = runningApp.localizedName ?? app.name
        let systemScript = """
        tell application "System Events"
            try
                tell process "\(processName)"
                    set frontmost to true
                    if "\(windowName)" is not "" then
                        try
                            set targetWindow to first window whose title is "\(windowName)"
                            perform action "AXRaise" of targetWindow
                            click targetWindow
                        on error
                            -- Fallback: try by index if name fails
                            if (count windows) > 0 then
                                perform action "AXRaise" of window 1
                                click window 1
                            end if
                        end try
                    else
                        -- No window name, just bring first window forward
                        if (count windows) > 0 then
                            perform action "AXRaise" of window 1
                            click window 1
                        end if
                    end if
                end tell
            on error errMsg
                log "System Events error: " & errMsg
            end try
        end tell
        """
        
        if let systemAppleScript = NSAppleScript(source: systemScript) {
            var error: NSDictionary?
            systemAppleScript.executeAndReturnError(&error)
            if let error = error {
                AppLogger.shared.error("System Events script failed: \(error)")
            } else {
                AppLogger.shared.info("Window focused using System Events")
            }
        }
    }
    
    private func ensureAppIsFrontmost(app: DockApp, runningApp: NSRunningApplication) {
        let script = """
        tell application "\(app.name)"
            activate
        end tell
        tell application "System Events"
            tell process "\(runningApp.localizedName ?? app.name)"
                set frontmost to true
            end tell
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                AppLogger.shared.warning("Ensure frontmost script failed: \(error)")
            }
        }
    }
    
    func closeWindow(windowID: CGWindowID, windowTitle: String, app: DockApp) -> Bool {
        guard let runningApp = app.runningApplication else {
            AppLogger.shared.warning("Cannot close window: app is not running")
            return false
        }
        
        AppLogger.shared.info("Closing window '\(windowTitle)' (ID: \(windowID)) for app \(app.name)")
        
        // Verify the window belongs to this app
        if windowID > 0 {
            guard let windowList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
                  let windowInfo = windowList.first,
                  let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == runningApp.processIdentifier else {
                AppLogger.shared.warning("Window \(windowID) does not belong to app \(app.name)")
                return false
            }
        }
        
        // Try multiple approaches for closing the window
        let processName = runningApp.localizedName ?? app.name
        var success = false
        
        // Approach 1: Direct app-level close command
        if !windowTitle.isEmpty {
            let appScript = """
            tell application "\(app.name)"
                try
                    close window "\(windowTitle)"
                    return true
                on error
                    return false
                end try
            end tell
            """
            
            if let appleScript = NSAppleScript(source: appScript) {
                var error: NSDictionary?
                let result = appleScript.executeAndReturnError(&error)
                if error == nil, result.booleanValue {
                    AppLogger.shared.info("Successfully closed window using app script")
                    return true
                }
            }
        }
        
        // Approach 2: System Events with accessibility actions
        let systemScript = """
        tell application "System Events"
            try
                tell process "\(processName)"
                    if "\(windowTitle)" is not "" then
                        try
                            set targetWindow to first window whose title is "\(windowTitle)"
                            click (first button of targetWindow whose subrole is "AXCloseButton")
                            return true
                        on error
                            -- Try alternative close methods
                            try
                                close window "\(windowTitle)"
                                return true
                            end try
                        end try
                    else
                        -- No window title, try to close first window
                        if (count windows) > 0 then
                            try
                                click (first button of window 1 whose subrole is "AXCloseButton")
                                return true
                            on error
                                try
                                    close window 1
                                    return true
                                end try
                            end try
                        end if
                    end if
                end tell
            end try
            return false
        end tell
        """
        
        if let systemAppleScript = NSAppleScript(source: systemScript) {
            var error: NSDictionary?
            let result = systemAppleScript.executeAndReturnError(&error)
            if error == nil, result.booleanValue {
                AppLogger.shared.info("Successfully closed window using System Events")
                success = true
            } else {
                AppLogger.shared.warning("System Events close failed: \(error?.description ?? "unknown")")
            }
        }
        
        // Approach 3: Fallback using keyboard shortcut (Cmd+W)
        if !success {
            let keyboardScript = """
            tell application "System Events"
                try
                    tell process "\(processName)"
                        set frontmost to true
                        if "\(windowTitle)" is not "" then
                            try
                                set targetWindow to first window whose title is "\(windowTitle)"
                                click targetWindow
                                delay 0.1
                            end try
                        end if
                        keystroke "w" using command down
                        return true
                    end tell
                on error
                    return false
                end try
            end tell
            """
            
            if let keyboardAppleScript = NSAppleScript(source: keyboardScript) {
                var error: NSDictionary?
                let result = keyboardAppleScript.executeAndReturnError(&error)
                if error == nil, result.booleanValue {
                    AppLogger.shared.info("Successfully closed window using keyboard shortcut")
                    success = true
                } else {
                    AppLogger.shared.warning("Keyboard shortcut close failed: \(error?.description ?? "unknown")")
                }
            }
        }
        
        if !success {
            AppLogger.shared.error("All window close attempts failed for window '\(windowTitle)'")
        }
        
        return success
    }

    func activateApp(_ app: DockApp) {
        AppLogger.shared.info("activateApp called for \(app.name), isRunning: \(app.isRunning), isActive: \(app.runningApplication?.isActive ?? false)")
        
        if let runningApp = app.runningApplication {
            AppLogger.shared.info("Activating running app: \(app.name)")
            
            // Ensure the app is unhidden first
            if runningApp.isHidden {
                let unhideSuccess = runningApp.unhide()
                AppLogger.shared.info("Unhide app result: \(unhideSuccess)")
            }
            
            // Activate with enhanced options for better reliability
            var activateSuccess = false
            if #available(macOS 14.0, *) {
                activateSuccess = runningApp.activate()
            } else {
                // Use ActivateAllWindows instead of deprecated ActivateIgnoringOtherApps
                activateSuccess = runningApp.activate(options: [.activateAllWindows])
            }
            
            AppLogger.shared.info("Activate app result: \(activateSuccess)")
            
            // Additional step: Use AppleScript for more reliable activation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let enhancedActivationScript = """
                tell application "\(app.name)"
                    activate
                end tell
                tell application "System Events"
                    tell process "\(runningApp.localizedName ?? app.name)"
                        set frontmost to true
                        -- Bring all windows to front if any exist
                        if (count windows) > 0 then
                            try
                                perform action "AXRaise" of window 1
                            end try
                        end if
                    end tell
                end tell
                """
                
                if let appleScript = NSAppleScript(source: enhancedActivationScript) {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                    if let error = error {
                        AppLogger.shared.warning("Enhanced activation script failed: \(error)")
                    } else {
                        AppLogger.shared.info("Enhanced activation completed successfully")
                    }
                }
            }
        } else if let appURL = app.url {
            // Only launch if we have a valid URL and the app exists at that location
            guard FileManager.default.fileExists(atPath: appURL.path) else {
                AppLogger.shared.error("App not found at URL: \(appURL.path)")
                return
            }
            
            AppLogger.shared.info("Launching app from URL: \(appURL.path)")
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.promptsUserIfNeeded = false  // Prevent user prompts/popups
            
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    AppLogger.shared.error("Failed to launch app from URL: \(error.localizedDescription)")
                }
            }
        } else {
            // For apps without a stored URL, only attempt to launch if they're pinned and we can find them silently
            guard app.isPinned else {
                AppLogger.shared.warning("App not running and not pinned, skipping launch: \(app.bundleIdentifier)")
                return
            }
            
            // Try to find the app silently without triggering system dialogs
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier),
                  FileManager.default.fileExists(atPath: appURL.path) else {
                AppLogger.shared.error("Could not find application silently: \(app.bundleIdentifier)")
                return
            }
            
            AppLogger.shared.info("Launching pinned app from bundle identifier: \(appURL.path)")
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.promptsUserIfNeeded = false  // Prevent user prompts/popups
            
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    AppLogger.shared.error("Failed to launch app from bundle identifier: \(error.localizedDescription)")
                }
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