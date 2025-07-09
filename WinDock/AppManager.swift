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
    private var accessibilityElement: AXUIElement?

    // Default pinned applications - Windows 11 style defaults
    private let defaultPinnedApps = [
        "com.apple.finder",          // File Explorer equivalent
        "com.apple.Safari",           // Edge equivalent
        "com.apple.systempreferences", // Settings
        "com.apple.mail",             // Mail
        "com.apple.launchpad"         // Start menu equivalent
    ]

    init() {
        loadPinnedApps()
        loadDockAppOrder()
        setupAccessibility()
        updateDockApps()
    }
    
    private func setupAccessibility() {
        // Request accessibility permissions if needed
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if accessEnabled {
            accessibilityElement = AXUIElementCreateSystemWide()
        }
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
    }
    
    func stopMonitoring() {
        appMonitorTimer?.invalidate()
        appMonitorTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
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
    
    private func updateDockApps() {
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

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
    
    // MARK: - App Actions
    
    func activateApp(_ app: DockApp) {
        if let runningApp = app.runningApplication {
            // If app has multiple windows, cycle through them
            if app.windowCount > 1 && runningApp.isActive {
                cycleWindows(for: app)
            } else {
                if #available(macOS 14.0, *) {
                    runningApp.activate()
                } else {
                    runningApp.activate(options: [.activateIgnoringOtherApps])
                }
            }
        } else if let appURL = app.url {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        } else {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
                let configuration = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
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
        app.runningApplication?.hide()
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
                runningApp.activate(options: [.activateAllWindows])
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
}