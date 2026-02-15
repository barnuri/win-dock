import SwiftUI
import AppKit
import Foundation
import Darwin
import ObjectiveC
import SettingsAccess

// Import for ProcessSerialNumber and TransformProcessType
#if os(macOS)
import ApplicationServices
#endif

private func setGlobalErrorHandlers() {
    NSSetUncaughtExceptionHandler { exception in
        AppLogger.shared.error("Uncaught exception: \(exception)\nStack: \(exception.callStackSymbols.joined(separator: "\n"))")
    }
    signal(SIGABRT) { _ in AppLogger.shared.error("Received SIGABRT"); exit(EXIT_FAILURE) }
    signal(SIGILL)  { _ in AppLogger.shared.error("Received SIGILL"); exit(EXIT_FAILURE) }
    signal(SIGSEGV) { _ in AppLogger.shared.error("Received SIGSEGV"); exit(EXIT_FAILURE) }
    signal(SIGFPE)  { _ in AppLogger.shared.error("Received SIGFPE"); exit(EXIT_FAILURE) }
    signal(SIGBUS)  { _ in AppLogger.shared.error("Received SIGBUS"); exit(EXIT_FAILURE) }
    signal(SIGPIPE) { _ in AppLogger.shared.error("Received SIGPIPE"); exit(EXIT_FAILURE) }
}

@main
struct Main: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Start the WindowsResizeManager only if enabled in settings
        if UserDefaults.standard.bool(forKey: "enableWindowsResize") {
            WindowsResizeManager.shared.start()
        }
    }

    var body: some Scene {
        WindowGroup("WinDock") {
            // Main content view with minimal size to ensure app is visible in dock
            ZStack {
                Color.clear
                    .frame(width: 0, height: 0)
                    .opacity(0.01) // Very slight opacity to keep window registered

                // Hidden helper for SettingsAccess
                SettingsAccessHelper()
            }
            .openSettingsAccess()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Settings scene - this integrates with standard Command+, shortcut
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var dockWindows: [DockWindow] = []
    var statusBarItem: NSStatusItem?
    @AppStorage("dockPosition") var dockPosition: DockPosition = .bottom
    private var isUpdatingDockWindows = false
    private var lastDockPosition: DockPosition = .bottom
    private var lastDockSize: String = "medium"
    private var lastPaddingVertical: Double = 0.0
    private var lastPaddingHorizontal: Double = 0.0
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setGlobalErrorHandlers()
        
        // Initialize tracking variables
        lastDockPosition = dockPosition
        lastDockSize = UserDefaults.standard.string(forKey: "dockSize") ?? "medium"
        lastPaddingVertical = UserDefaults.standard.double(forKey: "paddingVertical")
        lastPaddingHorizontal = UserDefaults.standard.double(forKey: "paddingHorizontal")
        
        // Start background update manager for real-time clock and system info
        Task { @MainActor in
            BackgroundUpdateManager.shared.startBackgroundUpdates()
        }
        
        // Initialize LoginItemManager to ensure launch-at-login is registered
        // on first launch (the singleton sets it up in its init)
        _ = LoginItemManager.shared

        // Initialize NotificationPositionManager to start background monitoring
        // This ensures notification positioning works immediately when app launches,
        // not just when settings page is opened
        _ = NotificationPositionManager.shared
        
        // Ensure the app shows up in the dock (counteract LSUIElement if needed)
        ensureAppVisibility()
        
        // Ensure we have a proper application menu
        setupApplicationMenu()
        
        // Setup the rest of the app
        setupStatusBarItem()
        setupDockWindowsForAllScreens()
        
        // Start WindowsResizeManager if enabled in settings
        if UserDefaults.standard.bool(forKey: "enableWindowsResize") {
            WindowsResizeManager.shared.start()
        }
        
        // Check and request Apple Events authorization for app integrations
        checkAndRequestAppleEventsAuthorization()
        
        // Ensure app is properly activated
        NSApp.activate(ignoringOtherApps: true)
        
        // Register for notifications
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersDidChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsDidChange), name: UserDefaults.didChangeNotification, object: nil)
        
        // Log that we've started
        AppLogger.shared.info("Application finished launching - dock position: \(dockPosition.rawValue)")
    }
    
    private func ensureAppVisibility() {
        // This ensures app is visible in dock and shows menu bar
        
        // Set activation policy to regular to ensure app appears in dock
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            AppLogger.shared.info("Set application activation policy to regular")
        }
        
        // Activate the app
        NSApp.activate(ignoringOtherApps: true)
        
        // Log the process state change
        AppLogger.shared.info("Ensured app visibility in dock")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.shared.info("Application will terminate")
        WindowsResizeManager.shared.stop()
        NotificationPositionManager.shared.stop()
    }
    
    
    private func setupApplicationMenu() {
        // Create the main menu for the application
        let mainMenu = NSMenu()
        
        // Application menu (first menu)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
               
        // Separator
        appMenu.addItem(NSMenuItem.separator())
        
        // Settings item with the standard Command+Comma shortcut
        let prefsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsMenu), keyEquivalent: ",")
        prefsItem.target = self
        appMenu.addItem(prefsItem)
        
        // Separator
        appMenu.addItem(NSMenuItem.separator())
        
        // Services submenu
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        
        // Register the services menu
        NSApp.servicesMenu = servicesMenu
        
        // Separator
        appMenu.addItem(NSMenuItem.separator())
        
        // Standard application items
        let hideItem = NSMenuItem(title: "Hide Win Dock", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.target = NSApp
        appMenu.addItem(hideItem)
        
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp
        appMenu.addItem(hideOthersItem)
        
        let showAllItem = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        showAllItem.target = NSApp
        appMenu.addItem(showAllItem)
        
        // Separator
        appMenu.addItem(NSMenuItem.separator())
        
        // Restart item
        let restartItem = NSMenuItem(title: "Restart Win Dock", action: #selector(restartApp), keyEquivalent: "r")
        restartItem.keyEquivalentModifierMask = [.command, .shift]
        restartItem.target = self
        appMenu.addItem(restartItem)
        
        // Quit item
        let quitItem = NSMenuItem(title: "Quit Win Dock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        appMenu.addItem(quitItem)
        
        // Add app menu to main menu
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        
        // Standard edit menu items
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        
        // Add hide/show dock option
        let visibilityManager = DockVisibilityManager.shared
        let visibilityMenuItem = NSMenuItem(title: visibilityManager.visibilityDisplayName, action: #selector(toggleDockVisibility), keyEquivalent: "")
        visibilityMenuItem.target = self
        viewMenu.addItem(visibilityMenuItem)
        
        viewMenu.addItem(NSMenuItem.separator())
        
        // Add dock position submenu
        let positionMenu = NSMenu()
        for pos in DockPosition.allCases {
            let item = NSMenuItem(title: pos.rawValue.capitalized, action: #selector(changeDockPosition(_:)), keyEquivalent: "")
            item.target = self
            item.state = (pos == dockPosition) ? .on : .off
            item.representedObject = pos.rawValue
            positionMenu.addItem(item)
        }
        let positionItem = NSMenuItem(title: "Dock Position", action: nil, keyEquivalent: "")
        positionItem.submenu = positionMenu
        viewMenu.addItem(positionItem)
        
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
        
        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        // Register window menu
        NSApp.windowsMenu = windowMenu
        
        // Help menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        
        helpMenu.addItem(NSMenuItem(title: "Win Dock Help", action: #selector(NSApplication.showHelp(_:)), keyEquivalent: "?"))
        
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        
        // Set the menu
        NSApp.mainMenu = mainMenu
        
        AppLogger.shared.info("Application menu set up successfully")
    }
    
   
    private func setupStatusBarItem() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        // Try to create status button
        guard let statusButton = statusBarItem?.button else {
            AppLogger.shared.error("Could not create status bar button")
            return
        }

        // Multi-layered approach to load icon with logging
        do {
            var iconImage: NSImage?
            var iconSource = ""
            
            // Try multiple methods to load icon with fallbacks
            // Method 1: Asset catalog
            if let assetIcon = NSImage(named: "AppIcon") {
                iconImage = assetIcon
                iconSource = "asset catalog (AppIcon)"
            }
            // Method 2: Bundle resources
            else if let iconPath = Bundle.main.path(forResource: "icon", ofType: "png"),
                     let fileIcon = NSImage(contentsOfFile: iconPath) {
                iconImage = fileIcon
                iconSource = "bundle path: \(iconPath)"
            }
            // Method 3: App icon from bundle or system symbol fallback
            else {
                // First try bundle icon
                iconImage = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
                iconSource = "app bundle icon"
                
                // If we still don't have a valid icon, try system symbol
                if iconImage == nil, let symbolIcon = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Win Dock") {
                    iconImage = symbolIcon
                    iconSource = "system symbol fallback"
                    AppLogger.shared.warning("Failed to load custom icon, using fallback system symbol")
                }
                
                // If all methods failed, throw an error
                if iconImage == nil {
                    throw NSError(domain: "WinDock", code: 100, userInfo: [NSLocalizedDescriptionKey: "All icon loading methods failed"])
                }
            }
            
            // Resize icon to fit nicely in the status bar (18x18 is good for menu bar)
            guard let icon = iconImage else {
                throw NSError(domain: "WinDock", code: 101, userInfo: [NSLocalizedDescriptionKey: "Icon image is nil after loading attempts"])
            }
            
            let resizedIcon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                icon.draw(in: rect)
                return true
            }
            
            statusButton.image = resizedIcon
            AppLogger.shared.info("Status bar icon successfully loaded from \(iconSource)")
            
            // Configure button
            statusButton.action = #selector(statusBarItemClicked)
            statusButton.target = self
            
        } catch {
            AppLogger.shared.error("Failed to set status bar icon", error: error)
            // Final fallback - text-only button
            statusButton.title = "WD"
        }

        // Create menu for status bar item
        let menu = NSMenu()
        
        // Add app name with icon at the top, disabled
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Win Dock"
        let appNameItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        
        // Add app icon to the menu item (try multiple sources)
        // No need for do-catch since we're not throwing anything
        var menuIcon: NSImage?
        
        if let customIcon = NSImage(named: "AppIcon") {
            menuIcon = customIcon
        } else if let iconPath = Bundle.main.path(forResource: "icon", ofType: "png"),
                  let fileIcon = NSImage(contentsOfFile: iconPath) {
            menuIcon = fileIcon
        } else {
            menuIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        }
        
        if let icon = menuIcon {
            // Resize icon to fit nicely in menu item (16x16 is standard)
            let resizedIcon = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                icon.draw(in: rect)
                return true
            }
            appNameItem.image = resizedIcon
        } else {
            AppLogger.shared.error("Failed to set menu item icon - no valid icon found")
        }
        
        appNameItem.isEnabled = false
        menu.addItem(appNameItem)
        menu.addItem(NSMenuItem.separator())
        
       
        // Hide/Show Dock option
        let visibilityManager = DockVisibilityManager.shared
        let visibilityItem = NSMenuItem(title: visibilityManager.visibilityDisplayName, action: #selector(toggleDockVisibility), keyEquivalent: "")
        visibilityItem.target = self
        menu.addItem(visibilityItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings menu item
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // Show logs menu item
        let logsItem = NSMenuItem(title: "Show Logs", action: #selector(showLogsFolder), keyEquivalent: "")
        logsItem.target = self
        menu.addItem(logsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add dock position submenu
        let positionMenu = NSMenu()
        for pos in DockPosition.allCases {
            let item = NSMenuItem(title: pos.rawValue.capitalized, action: #selector(changeDockPosition(_:)), keyEquivalent: "")
            item.target = self
            item.state = (pos == dockPosition) ? .on : .off
            item.representedObject = pos.rawValue
            positionMenu.addItem(item)
        }
        let positionItem = NSMenuItem(title: "Dock Position", action: nil, keyEquivalent: "")
        menu.setSubmenu(positionMenu, for: positionItem)
        menu.addItem(positionItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Restart menu item
        let restartItem = NSMenuItem(title: "Restart Win Dock", action: #selector(restartApp), keyEquivalent: "")
        restartItem.target = self
        menu.addItem(restartItem)
        
        // Quit menu item
        let quitItem = NSMenuItem(title: "Quit Win Dock", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusBarItem?.menu = menu
    }
    
    @objc private func statusBarItemClicked() {
        // Show dock window on all displays and bring to front
        for dockWindow in dockWindows {
            dockWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .participatesInCycle]
            dockWindow.level = .normal
            dockWindow.orderFrontRegardless()
            dockWindow.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupDockWindowsForAllScreens() {
        // Prevent multiple simultaneous updates
        guard !isUpdatingDockWindows else { return }
        isUpdatingDockWindows = true
        
        // Remove old windows more thoroughly
        for window in dockWindows {
            window.orderOut(nil)
            window.close()
        }
        dockWindows.removeAll()
        
        // Small delay to ensure windows are fully closed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Create a DockWindow for each screen
            for screen in NSScreen.screens {
                let dockWindow = DockWindow()
                let frame = dockFrame(for: self.dockPosition, screen: screen)
                dockWindow.setFrame(frame, display: true)
                dockWindow.show()
                self.dockWindows.append(dockWindow)
            }
            self.isUpdatingDockWindows = false
        }
    }

    // Call this method whenever the dock position changes (from settings or menu)
    func updateDockPosition(_ newPosition: DockPosition) {
        dockPosition = newPosition
        setupDockWindowsForAllScreens()
        setupStatusBarItem() // update menu checkmarks
    }

    @objc private func changeDockPosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let pos = DockPosition(rawValue: raw) else { return }
        updateDockPosition(pos)
    }

    @objc private func screenParametersDidChange() {
        setupDockWindowsForAllScreens()
    }
    
    @objc private func userDefaultsDidChange() {
        // Only update if dock-related settings have changed
        let currentDockSize = UserDefaults.standard.string(forKey: "dockSize") ?? "medium"
        let currentPaddingVertical = UserDefaults.standard.double(forKey: "paddingVertical")
        let currentPaddingHorizontal = UserDefaults.standard.double(forKey: "paddingHorizontal")
        
        if dockPosition != lastDockPosition || 
           currentDockSize != lastDockSize ||
           currentPaddingVertical != lastPaddingVertical ||
           currentPaddingHorizontal != lastPaddingHorizontal {
            
            lastDockPosition = dockPosition
            lastDockSize = currentDockSize
            lastPaddingVertical = currentPaddingVertical
            lastPaddingHorizontal = currentPaddingHorizontal
            
            DispatchQueue.main.async {
                self.setupDockWindowsForAllScreens()
                self.setupStatusBarItem() // update menu checkmarks
            }
        }
    }
    
    // Static method that can be called from anywhere
    static func openSettingsWindow() {
        DispatchQueue.main.async {
            if let delegate = NSApp.delegate as? AppDelegate {
                // Use the full implementation in the app delegate
                delegate.openSettings()
            } else {
                // Fallback if delegate is not available
                NSApp.activate(ignoringOtherApps: true)
                let _ = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) ||
                       NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                AppLogger.shared.info("Settings window opened via static method (delegate not available)")
            }
        }
    }
    
    @objc func openSettingsMenu() {
        openSettings()
    }

    @objc func openSettings() {
        AppLogger.shared.info("Opening settings window")
        NSApp.activate(ignoringOtherApps: true)
        
        // Use SettingsHelper to trigger settings opening via SettingsAccess
        SettingsHelper.shared.requestOpenSettings()
    }
    @objc func showLogsFolder() {
        AppLogger.shared.info("Opening logs folder")
        AppLogger.shared.showLogsInFinder()
    }
    
    @objc private func restartApp() {
        AppLogger.shared.info("Restarting WinDock from menu")
        restartApplication()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func toggleDockVisibility() {
        DockVisibilityManager.shared.toggleVisibility()
    }
    
    private func checkAndRequestAppleEventsAuthorization() {
        // Test Apple Events authorization by executing a simple script
        let testScript = """
        tell application "System Events"
            get name of processes
        end tell
        """
        
        DispatchQueue.global(qos: .utility).async {
            if let appleScript = NSAppleScript(source: testScript) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                
                DispatchQueue.main.async {
                    if let error = error {
                        let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
                        
                        if errorNumber == -1743 {
                            AppLogger.shared.warning("Apple Events authorization required. User will need to grant permission in System Preferences > Security & Privacy > Privacy > Automation for WinDock to control other applications.")
                            
                            // Show user-friendly notification
                            self.showAppleEventsPermissionAlert()
                        } else {
                            AppLogger.shared.error("Apple Events test error: \(error)")
                        }
                    } else {
                        AppLogger.shared.info("Apple Events authorization is working correctly")
                    }
                }
            }
        }
    }
    
    private func restartApplication() {
        let appPath = Bundle.main.bundlePath
        let relaunchPath = "/usr/bin/open"
        
        // Create a task to relaunch the app
        let task = Process()
        task.executableURL = URL(fileURLWithPath: relaunchPath)
        task.arguments = ["-n", appPath]
        
        do {
            try task.run()
            AppLogger.shared.info("Successfully initiated app restart")
            // Quit current instance after launching new one
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            AppLogger.shared.error("Failed to restart application: \(error)")
            // Show error alert to user
            let alert = NSAlert()
            alert.messageText = "Restart Failed"
            alert.informativeText = "Failed to restart WinDock: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    private func showAppleEventsPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Permission Required"
        alert.informativeText = "WinDock needs permission to control other applications to show notification badges and provide app integrations. Please:\n\n1. Open System Preferences\n2. Go to Security & Privacy > Privacy > Automation\n3. Enable WinDock to control System Events and other applications"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open Security & Privacy preferences
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

enum DockPosition: String, CaseIterable {
    case bottom, top, left, right
    
    var displayName: String {
        switch self {
        case .bottom: return "Bottom"
        case .top: return "Top"
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

