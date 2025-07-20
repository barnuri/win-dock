import Foundation
import AppKit
import Combine
import Accessibility

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
        
        // Set up periodic updates with higher frequency for better responsiveness
        appMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                self.updateDockApps()
            }
        }
        
        // Listen for app launch/quit notifications
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
        
        // Listen for window changes
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        
        // Register screen insets for the dock
        registerDockInsets()
    }
    
    func stopMonitoring() {
        appMonitorTimer?.invalidate()
        appMonitorTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        unregisterDockInsets()
    }
    
    @objc private func appDidLaunch(_ notification: Notification) {
        Task { @MainActor in
            updateDockApps()
        }
    }
    
    @objc private func appDidTerminate(_ notification: Notification) {
        Task { @MainActor in
            updateDockApps()
        }
    }
    
    @objc private func activeSpaceDidChange(_ notification: Notification) {
        Task { @MainActor in
            updateDockApps()
        }
    }
    
    // Public function to trigger update from outside
    func updateDockAppsIfNeeded() {
        Task { @MainActor in
            updateDockApps()
        }
    }
    
    private func updateDockApps() {
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
            
            let windows = getWindowsForApp(app)
            let windowCount = windows.filter { !$0.isMinimized }.count

            let dockApp = DockApp(
                bundleIdentifier: bundleId,
                name: app.localizedName ?? bundleId,
                icon: app.icon,
                url: app.bundleURL,
                isRunning: true,
                isPinned: pinnedBundleIdentifiers.contains(bundleId),
                windowCount: windowCount,
                runningApplication: app,
                windows: windows
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
        
        // Use Core Graphics to get window information
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
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
            
            // Skip windows that are likely not user-visible
            if bounds.width < 50 || bounds.height < 50 || alpha < 0.1 {
                continue
            }
            
            let window = WindowInfo(
                title: title,
                windowID: windowID,
                bounds: bounds,
                isMinimized: !isOnScreen,
                isOnScreen: isOnScreen
            )
            
            windows.append(window)
        }
        
        return windows
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
            runningApplication: nil
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
        
        // If we have a specific window ID, try to focus it
        if windowID > 0 {
            // Use AppleScript to focus the specific window
            let script = """
            tell application "System Events"
                tell process "\(app.name)"
                    set frontmost to true
                    try
                        perform action "AXRaise" of window 1
                    end try
                end tell
            end tell
            """
            
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    AppLogger.shared.error("Focus window AppleScript error: \(error)")
                }
            }
        }
    }

    func activateApp(_ app: DockApp) {
        AppLogger.shared.info("activateApp called for \(app.name), isRunning: \(app.isRunning), isActive: \(app.runningApplication?.isActive ?? false)")
        if let runningApp = app.runningApplication {
            // Force app to front and activate
            AppLogger.shared.info("Activating running app: \(app.name)")
            
            if #available(macOS 14.0, *) {
                runningApp.activate()
            } else {
                runningApp.activate(options: [.activateIgnoringOtherApps])
            }
            
            // Ensure the app is unhidden if it was hidden
            if runningApp.isHidden {
                runningApp.unhide()
            }
            
            // Force the app to the front using NSApplication
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
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
    
    // MARK: - Screen Insets for Dock
    
    private func registerDockInsets() {
        // Register the dock area with the system to prevent maximized windows from overlapping
        AppLogger.shared.info("Registering dock insets")
        
        // Get dock position and size from UserDefaults
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let dockPosition = appDelegate.dockPosition
        let dockHeight = getDockHeight()
        
        // Reserve screen space for each screen
        for screen in NSScreen.screens {
            reserveScreenSpace(for: screen, position: dockPosition, size: dockHeight)
        }
    }
    
    private func unregisterDockInsets() {
        AppLogger.shared.info("Unregistering dock insets")
        
        // Remove screen space reservation for each screen
        for screen in NSScreen.screens {
            removeScreenSpaceReservation(for: screen)
        }
    }
    
    private func getDockHeight() -> CGFloat {
        let dockSize = UserDefaults.standard.string(forKey: "dockSize") ?? "medium"
        switch dockSize {
        case "small": return 48
        case "medium": return 56
        case "large": return 64
        default: return 56
        }
    }
    
    private func reserveScreenSpace(for screen: NSScreen, position: DockPosition, size: CGFloat) {
        // This uses private APIs to reserve screen space
        // In a production app, you might need to use a different approach
        
        let screenFrame = screen.frame
        var reservedArea = CGRect.zero
        
        switch position {
        case .bottom:
            reservedArea = CGRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: screenFrame.width,
                height: size
            )
        case .top:
            reservedArea = CGRect(
                x: screenFrame.minX,
                y: screenFrame.maxY - size,
                width: screenFrame.width,
                height: size
            )
        case .left:
            reservedArea = CGRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: size,
                height: screenFrame.height
            )
        case .right:
            reservedArea = CGRect(
                x: screenFrame.maxX - size,
                y: screenFrame.minY,
                width: size,
                height: screenFrame.height
            )
        }
        
        // Store the reserved area for later removal
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int ?? 0
        UserDefaults.standard.set(NSStringFromRect(reservedArea), forKey: "WinDock.ReservedArea.\(screenNumber)")
        
        // This is a simplified version - actual implementation would use CGSSetScreenResolution or similar
        AppLogger.shared.info("Reserved screen area: \(reservedArea) for screen: \(screen.localizedName)")
    }
    
    private func removeScreenSpaceReservation(for screen: NSScreen) {
        // Remove the previously reserved screen space
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int ?? 0
        let key = "WinDock.ReservedArea.\(screenNumber)"
        UserDefaults.standard.removeObject(forKey: key)
        
        AppLogger.shared.info("Removed screen space reservation for screen: \(screen.localizedName)")
    }
}