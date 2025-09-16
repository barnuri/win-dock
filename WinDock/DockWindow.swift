import CoreGraphics
import Darwin
import SwiftUI
import AppKit
import Combine
#if canImport(IOKit)
import IOKit
#endif
#if canImport(IOKit.ps)
import IOKit.ps
#endif

class DockWindow: NSPanel {
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    private static var sharedAppManager: AppManager = AppManager()
    private var appManager: AppManager { DockWindow.sharedAppManager }
    private var windowObserver: NSObjectProtocol?
    @AppStorage("dockSize") private var dockSize: DockSize = .medium
    @AppStorage("autoHide") private var autoHide = false
    @AppStorage("showOnAllSpaces") private var showOnAllSpaces = true
    @AppStorage("centerTaskbarIcons") private var centerTaskbarIcons = true
    @AppStorage("showSystemTray") private var showSystemTray = true
    @AppStorage("showTaskView") private var showTaskView = true
    @AppStorage("searchAppChoice") private var searchAppChoice = SearchAppChoice.spotlight
    
    private var hideTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private var dockView: NSHostingView<DockView>?
    private var cancellables = Set<AnyCancellable>()
    private let fullscreenManager = FullscreenDetectionManager.shared
    private let visibilityManager = DockVisibilityManager.shared
    
    convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 60),
                  styleMask: [.borderless, .nonactivatingPanel],
                  backing: .buffered,
                  defer: false)
        if !isPreview {
            setup()
        }
    }
    
    private func setup() {
        if isPreview { return }
        level = .floating // Use normal level to appear in Alt+Tab
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .participatesInCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        
        // Completely disable resizing - make window non-resizable
        styleMask.remove(.resizable)
        
        // Set fixed size constraints
        let dockHeight = getDockHeight()
        minSize = NSSize(width: 100, height: dockHeight)
        maxSize = NSSize(width: NSScreen.main?.frame.width ?? 1920, height: dockHeight)
        
        // Enhanced accessibility and app switcher support
        self.setAccessibilityTitle("WinDock Taskbar")
        self.setAccessibilityRole(.application)
        self.setAccessibilitySubrole(.standardWindow)
        
        // Set a proper window title for app switcher
        self.title = "WinDock Taskbar"

        // Set initial alpha value - always start visible
        alphaValue = 1.0
        
        updatePosition()
        appManager.startMonitoring()
        
        // Register the dock window with the visibility manager
        visibilityManager.addDockWindow(self)
        
        // Start fullscreen detection for auto-hide functionality
        fullscreenManager.startMonitoring()
        
        // Subscribe to fullscreen state changes
        fullscreenManager.$hasFullscreenWindow
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasFullscreen in
                self?.handleFullscreenStateChange(hasFullscreen)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        windowObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.updatePosition()
            self.updateDockView()
            self.handleAutoHideSettingChange()
        }

        setupDockView()
        setupTrackingArea()
    }
    
    private func handleFullscreenStateChange(_ hasFullscreen: Bool) {
        if hasFullscreen {
            // Always hide dock when there's a fullscreen window (Windows-like behavior)
            // Use the visibility manager's dedicated fullscreen method
            visibilityManager.hideForFullscreen()
            AppLogger.shared.info("Dock hidden due to fullscreen window")
        } else {
            // Show dock when no fullscreen windows, unless manually hidden
            visibilityManager.showAfterFullscreen()
            AppLogger.shared.debug("Dock shown - no fullscreen windows")
        }
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    private func setupDockView() {
        let dockView = DockView()
        let hostingView = NSHostingView(rootView: dockView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        contentView = hostingView
        self.dockView = hostingView
    }
    
    private func updateDockView() {
        guard let hostingView = dockView else { return }
        hostingView.rootView = DockView()
        setupTrackingArea()
    }
    
    private func handleAutoHideSettingChange() {
        // If auto-hide is off, ensure the dock is fully visible
        if !autoHide && alphaValue < 1.0 {
            hideTimer?.invalidate()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                animator().alphaValue = 1.0
            }
        }
    }
    
    private func setupTrackingArea() {
        if let existingTrackingArea = trackingArea {
            contentView?.removeTrackingArea(existingTrackingArea)
        }
        
        trackingArea = NSTrackingArea(
            rect: contentView?.bounds ?? .zero,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        
        if let trackingArea = trackingArea {
            contentView?.addTrackingArea(trackingArea)
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        hideTimer?.invalidate()
        if autoHide {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                animator().alphaValue = 1.0
            }
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if autoHide {
            hideTimer?.invalidate()
            hideTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    self?.animator().alphaValue = 0.0
                }
            }
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        let locationInWindow = event.locationInWindow
        _ = contentView?.convert(locationInWindow, from: nil) ?? .zero
        let menu = NSMenu()
        // Position submenu
        let positionMenu = NSMenu()
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        for position in DockPosition.allCases {
            let item = NSMenuItem(
                title: position.displayName,
                action: #selector(changePosition(_:)),
                keyEquivalent: ""
            )
            item.representedObject = position.rawValue
            item.target = self
            item.state = position.rawValue == appDelegate.dockPosition.rawValue ? .on : .off
            positionMenu.addItem(item)
        }
        let positionItem = NSMenuItem(title: "Taskbar Position", action: nil, keyEquivalent: "")
        positionItem.submenu = positionMenu
        menu.addItem(positionItem)
        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(
            title: "Quit Win Dock",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        menu.popUp(positioning: nil, at: locationInWindow, in: self.contentView)
    }
    
    @objc private func changePosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let position = DockPosition(rawValue: raw),
              let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appDelegate.updateDockPosition(position)
    }
    
    @objc private func openSettings() {
        AppLogger.shared.info("Opening settings from DockWindow context menu")
        SettingsHelper.shared.requestOpenSettings()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func screenDidChange() {
        updatePosition()
    }
    
    private func updatePosition() {
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let screen = showOnAllSpaces ? NSScreen.main : NSScreen.screens.first else { return }
        let newFrame = dockFrame(for: appDelegate.dockPosition, screen: screen)
        setFrame(newFrame, display: true, animate: false)
        
        // Update size constraints based on dock position
        let dockHeight = getDockHeight()
        if appDelegate.dockPosition == .left || appDelegate.dockPosition == .right {
            // Vertical dock (disable resize)
            let size = NSSize(width: dockHeight, height: screen.frame.height)
            minSize = size
            maxSize = size
        } else {
            // Horizontal dock (disable resize)
            let size = NSSize(width: screen.frame.width, height: dockHeight)
            minSize = size
            maxSize = size
        }
        
        setupTrackingArea()
    }
    
    func cleanup() {
        appManager.stopMonitoring()
        fullscreenManager.stopMonitoring()
        cancellables.removeAll()
    }
    
    func show() {
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
    
    deinit {
        if !isPreview {
            NotificationCenter.default.removeObserver(self)
            if let observer = windowObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            cleanup()
        }
        // Unregister the dock window from the visibility manager
        visibilityManager.removeDockWindow(self)
    }
}


// Fixed lock screen function
func lockScreen() {
    let script = """
    tell application "System Events"
        keystroke "q" using {command down, control down}
    end tell
    """
    
    if let appleScript = NSAppleScript(source: script) {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error = error {
            AppLogger.shared.error("Lock screen error: \(error)")
            // Fallback to screen saver
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-a", "ScreenSaverEngine"]
            task.launch()
        } else {
            AppLogger.shared.info("Lock screen triggered successfully")
        }
    }
}
