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
struct WinDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup("WinDock") {
            // Main content view with minimal size to ensure app is visible in dock
            ZStack {
                ReservedPlace()
                    .frame(width: 1, height: 1)
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
    private var lastPaddingTop: Double = 0.0
    private var lastPaddingBottom: Double = 0.0
    private var lastPaddingLeft: Double = 0.0
    private var lastPaddingRight: Double = 0.0
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setGlobalErrorHandlers()
        
        // Initialize tracking variables
        lastDockPosition = dockPosition
        lastDockSize = UserDefaults.standard.string(forKey: "dockSize") ?? "medium"
        lastPaddingTop = UserDefaults.standard.double(forKey: "paddingTop")
        lastPaddingBottom = UserDefaults.standard.double(forKey: "paddingBottom")
        lastPaddingLeft = UserDefaults.standard.double(forKey: "paddingLeft")
        lastPaddingRight = UserDefaults.standard.double(forKey: "paddingRight")
        
        // Ensure the app shows up in the dock (counteract LSUIElement if needed)
        ensureAppVisibility()
        
        // Ensure we have a proper application menu
        setupApplicationMenu()
        
        // Setup the rest of the app
        setupStatusBarItem()
        setupDockWindowsForAllScreens()
        
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

    // Centralized frame calculation for dock position
    func dockFrame(for position: DockPosition, screen: NSScreen) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let dockHeight: CGFloat = getDockHeight()
        
        // Get padding values from UserDefaults
        let paddingTop = CGFloat(UserDefaults.standard.double(forKey: "paddingTop"))
        let paddingBottom = CGFloat(UserDefaults.standard.double(forKey: "paddingBottom"))
        let paddingLeft = CGFloat(UserDefaults.standard.double(forKey: "paddingLeft"))
        let paddingRight = CGFloat(UserDefaults.standard.double(forKey: "paddingRight"))
        
        switch position {
        case .bottom:
            // Use full screen frame for bottom to avoid safe area
            return NSRect(
                x: visibleFrame.minX + paddingLeft,
                y: visibleFrame.minY + paddingBottom,
                width: visibleFrame.width - paddingLeft - paddingRight,
                height: dockHeight
            )
        case .top:
            return NSRect(
                x: visibleFrame.minX + paddingLeft,
                y: visibleFrame.maxY - dockHeight - paddingTop,
                width: visibleFrame.width - paddingLeft - paddingRight,
                height: dockHeight
            )
        case .left:
            return NSRect(
                x: visibleFrame.minX + paddingLeft,
                y: visibleFrame.minY + paddingBottom,
                width: dockHeight,
                height: visibleFrame.height - paddingTop - paddingBottom
            )
        case .right:
            return NSRect(
                x: visibleFrame.maxX - dockHeight - paddingRight,
                y: visibleFrame.minY + paddingBottom,
                width: dockHeight,
                height: visibleFrame.height - paddingTop - paddingBottom
            )
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
        
        // Reserve screen space for the new dock position
        reserveScreenSpace()
        
        // Notify ReservedPlace to update its position if needed
        NotificationCenter.default.post(
            name: NSNotification.Name("WinDockPositionChanged"),
            object: nil,
            userInfo: nil
        )
        
        // Small delay to ensure windows are fully closed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Create a DockWindow for each screen
            for screen in NSScreen.screens {
                let dockWindow = DockWindow()
                let frame = self.dockFrame(for: self.dockPosition, screen: screen)
                dockWindow.setFrame(frame, display: true)
                dockWindow.show()
                self.dockWindows.append(dockWindow)
            }
            self.isUpdatingDockWindows = false
        }
    }

    private func reserveScreenSpace() {
        let dockHeight = getDockHeight()
        
        // Get padding values from UserDefaults
        let paddingTop = CGFloat(UserDefaults.standard.double(forKey: "paddingTop"))
        let paddingBottom = CGFloat(UserDefaults.standard.double(forKey: "paddingBottom"))
        let paddingLeft = CGFloat(UserDefaults.standard.double(forKey: "paddingLeft"))
        let paddingRight = CGFloat(UserDefaults.standard.double(forKey: "paddingRight"))
        
        // Reserve screen space for each screen to prevent window overlap
        for screen in NSScreen.screens {
            let screenFrame = screen.frame // Use full screen frame
            let visibleFrame = screen.visibleFrame
            var reservedArea = CGRect.zero
            
            switch dockPosition {
            case .bottom:
                // Use full screen frame for bottom to avoid safe area
                reservedArea = CGRect(
                    x: screenFrame.minX + paddingLeft,
                    y: screenFrame.minY + paddingBottom,
                    width: screenFrame.width - paddingLeft - paddingRight,
                    height: dockHeight
                )
            case .top:
                reservedArea = CGRect(
                    x: visibleFrame.minX + paddingLeft,
                    y: visibleFrame.maxY - dockHeight - paddingTop,
                    width: visibleFrame.width - paddingLeft - paddingRight,
                    height: dockHeight
                )
            case .left:
                reservedArea = CGRect(
                    x: visibleFrame.minX + paddingLeft,
                    y: visibleFrame.minY + paddingBottom,
                    width: dockHeight,
                    height: visibleFrame.height - paddingTop - paddingBottom
                )
            case .right:
                reservedArea = CGRect(
                    x: visibleFrame.maxX - dockHeight - paddingRight,
                    y: visibleFrame.minY + paddingBottom,
                    width: dockHeight,
                    height: visibleFrame.height - paddingTop - paddingBottom
                )
            }
            
            // Store the reserved area information
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int ?? 0
            let screenKey = "WinDock.ReservedArea.\(screenNumber)"
            UserDefaults.standard.set(NSStringFromRect(reservedArea), forKey: screenKey)
            
            AppLogger.shared.info("Reserved screen space: \(reservedArea) on screen \(screen.localizedName)")
        }
        
        // Notify other applications about the screen space reservation
        // This uses a notification that well-behaved apps might listen to
        NotificationCenter.default.post(
            name: NSNotification.Name("WinDockScreenSpaceReserved"),
            object: nil,
            userInfo: ["position": dockPosition.rawValue, "size": dockHeight]
        )
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
        let currentPaddingTop = UserDefaults.standard.double(forKey: "paddingTop")
        let currentPaddingBottom = UserDefaults.standard.double(forKey: "paddingBottom")
        let currentPaddingLeft = UserDefaults.standard.double(forKey: "paddingLeft")
        let currentPaddingRight = UserDefaults.standard.double(forKey: "paddingRight")
        
        if dockPosition != lastDockPosition || 
           currentDockSize != lastDockSize ||
           currentPaddingTop != lastPaddingTop ||
           currentPaddingBottom != lastPaddingBottom ||
           currentPaddingLeft != lastPaddingLeft ||
           currentPaddingRight != lastPaddingRight {
            
            lastDockPosition = dockPosition
            lastDockSize = currentDockSize
            lastPaddingTop = currentPaddingTop
            lastPaddingBottom = currentPaddingBottom
            lastPaddingLeft = currentPaddingLeft
            lastPaddingRight = currentPaddingRight
            
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
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
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

