import SwiftUI
import AppKit

class DockWindow: NSPanel {
    private let appManager = AppManager()
    private var windowObserver: NSObjectProtocol?
    @AppStorage("dockPosition") private var dockPosition: DockPosition = .bottom
    @AppStorage("dockSize") private var dockSize: DockSize = .medium
    @AppStorage("autoHide") private var autoHide = false
    @AppStorage("showOnAllSpaces") private var showOnAllSpaces = true
    @AppStorage("centerTaskbarIcons") private var centerTaskbarIcons = true
    @AppStorage("showSystemTray") private var showSystemTray = true
    @AppStorage("showTaskView") private var showTaskView = true
    @AppStorage("taskbarTransparency") private var taskbarTransparency = 0.8
    @AppStorage("searchAppChoice") private var searchAppChoice = SearchAppChoice.spotlight
    
    private var hideTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private var dockView: NSHostingView<DockContentView>?
    
    convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 60),
                  styleMask: [.borderless, .nonactivatingPanel],
                  backing: .buffered,
                  defer: false)
        setup()
    }
    
    private func setup() {
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        
        // Set dock to be non-resizable by other windows
        canBecomeKey = false
        canBecomeMain = false
        
        updatePosition()
        registerScreenReservedArea()
        
        appManager.startMonitoring()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        // Listen for settings changes
        windowObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePosition()
            self?.updateDockView()
            self?.registerScreenReservedArea()
        }
        
        setupDockView()
        setupTrackingArea()
        
        if autoHide {
            alphaValue = 0
        }
    }
    
    private func setupDockView() {
        let dockView = DockContentView(dockSize: dockSize)
        let hostingView = NSHostingView(rootView: dockView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        contentView = hostingView
        self.dockView = hostingView
    }
    
    private func updateDockView() {
        guard let hostingView = dockView else { return }
        hostingView.rootView = DockContentView(dockSize: dockSize)
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
        // Check if right-click is on the background (not on an app icon)
        let locationInWindow = event.locationInWindow
        _ = contentView?.convert(locationInWindow, from: nil) ?? .zero
        
        // Create context menu
        let menu = NSMenu()
        
        // Position submenu
        let positionMenu = NSMenu()
        for position in DockPosition.allCases {
            let item = NSMenuItem(
                title: position.displayName,
                action: #selector(changePosition(_:)),
                keyEquivalent: ""
            )
            item.representedObject = position
            item.target = self
            item.state = position == dockPosition ? .on : .off
            positionMenu.addItem(item)
        }
        
        let positionItem = NSMenuItem(title: "Taskbar Position", action: nil, keyEquivalent: "")
        positionItem.submenu = positionMenu
        menu.addItem(positionItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Win Dock",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Show menu at mouse location
        menu.popUp(positioning: nil, at: locationInWindow, in: self.contentView)
    }
    
    @objc private func changePosition(_ sender: NSMenuItem) {
        guard let position = sender.representedObject as? DockPosition else { return }
        dockPosition = position
        updatePosition()
        registerScreenReservedArea()
    }
    
    @objc private func openSettings() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.openSettings()
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func screenDidChange() {
        updatePosition()
        registerScreenReservedArea()
    }
    
    private func updatePosition() {
        guard let screen = showOnAllSpaces ? NSScreen.main : NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        let dockHeight = getDockHeight()
        let fullWidth = screenFrame.width
        
        var newFrame: NSRect
        
        switch dockPosition {
        case .bottom:
            newFrame = NSRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: fullWidth,
                height: dockHeight
            )
        case .top:
            // Account for menu bar
            let menuBarHeight: CGFloat = NSApplication.shared.mainMenu?.menuBarHeight ?? 24
            newFrame = NSRect(
                x: screenFrame.minX,
                y: screenFrame.maxY - dockHeight - menuBarHeight,
                width: fullWidth,
                height: dockHeight
            )
        case .left:
            newFrame = NSRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: dockHeight,
                height: screenFrame.height
            )
        case .right:
            newFrame = NSRect(
                x: screenFrame.maxX - dockHeight,
                y: screenFrame.minY,
                width: dockHeight,
                height: screenFrame.height
            )
        }
        
        setFrame(newFrame, display: true, animate: false)
        setupTrackingArea()
    }
    
    private func getDockHeight() -> CGFloat {
        switch dockSize {
        case .small: return 48
        case .medium: return 56
        case .large: return 64
        }
    }
    
    private func registerScreenReservedArea() {
        // Register the dock area to prevent window overlap
        if let screen = NSScreen.main {
            let dockHeight = getDockHeight()
            
            // This would need to use private APIs or system integration
            // to properly reserve screen space
            // For now, we'll use the window level to stay on top
            
            switch dockPosition {
            case .bottom, .top:
                // Reserve horizontal space
                AppLogger.shared.info("Reserving \(dockHeight)px \(dockPosition.rawValue) space")
            case .left, .right:
                // Reserve vertical space
                AppLogger.shared.info("Reserving \(dockHeight)px \(dockPosition.rawValue) space")
            }
        }
    }
    
    func cleanup() {
        appManager.stopMonitoring()
    }
    
    func show() {
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// Extension for DockPosition display names
extension DockPosition {
    var displayName: String {
        switch self {
        case .bottom: return "Bottom"
        case .top: return "Top"
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}