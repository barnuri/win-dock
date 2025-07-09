import SwiftUI
import AppKit

class DockWindow: NSObject {
    private var window: NSWindow?
    private var contentView: DockContentView?
    private var autoHideTimer: Timer?
    private var isHidden = false
    private var trackingArea: NSTrackingArea?
    
    // Settings properties
    @AppStorage("dockPosition") private var dockPosition: DockPosition = .bottom
    @AppStorage("dockSize") private var dockSize: DockSize = .medium
    @AppStorage("autoHide") private var autoHide = false
    @AppStorage("showOnAllSpaces") private var showOnAllSpaces = true
    @AppStorage("taskbarTransparency") private var taskbarTransparency = 0.8
    
    func show() {
        guard let screen = NSScreen.main else { return }
        
        let windowRect = NSRect(
            x: 0,
            y: 0,
            width: getDockWidth(for: screen),
            height: getDockHeight()
        )
        
        window = DockWindow.CustomWindow(
            contentRect: windowRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        guard let window = window else { return }
        
        // Configure window properties for Windows 11 style
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.canHide = false
        window.acceptsMouseMovedEvents = true
        
        // Configure collection behavior based on settings
        var collectionBehavior: NSWindow.CollectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]
        if showOnAllSpaces {
            collectionBehavior.insert(.canJoinAllSpaces)
        }
        window.collectionBehavior = collectionBehavior
        
        // Create and set content view with settings
        contentView = DockContentView(dockSize: dockSize)
        let hostingView = MouseTrackingHostingView(rootView: contentView!, dockWindow: self)
        window.contentView = hostingView
        
        // Position according to settings
        positionWindow()
        
        window.makeKeyAndOrderFront(nil)
        
        // Listen for screen changes and settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }
    
    private func getDockHeight() -> CGFloat {
        switch dockPosition {
        case .bottom, .top:
            return 48 // Windows 11 taskbar height
        case .left, .right:
            return NSScreen.main?.frame.height ?? 600
        }
    }
    
    private func getDockWidth(for screen: NSScreen) -> CGFloat {
        switch dockPosition {
        case .bottom, .top:
            return screen.frame.width
        case .left, .right:
            return 48 // Windows 11 taskbar width for vertical
        }
    }
    
    private func positionWindow() {
        guard let window = window else { return }
        
        let targetFrame = autoHide && isHidden ? getHiddenFrame() : getVisibleFrame()
        window.setFrame(targetFrame, display: true, animate: true)
        
        // Update tracking area after repositioning
        if autoHide {
            setupAutoHide()
        }
    }
    
    @objc private func screenDidChange() {
        positionWindow()
    }
    
    @objc private func settingsDidChange() {
        // Update window configuration when settings change
        guard let window = window else { return }
        
        // Update transparency
        window.alphaValue = CGFloat(taskbarTransparency)
        
        // Update collection behavior
        var collectionBehavior: NSWindow.CollectionBehavior = [.stationary, .ignoresCycle]
        if showOnAllSpaces {
            collectionBehavior.insert(.canJoinAllSpaces)
        }
        window.collectionBehavior = collectionBehavior
        
        // Update content view with new size
        contentView = DockContentView(dockSize: dockSize)
        let hostingView = MouseTrackingHostingView(rootView: contentView!, dockWindow: self)
        window.contentView = hostingView
        
        // Reposition and resize window
        positionWindow()
        
        // Setup auto-hide if enabled
        setupAutoHide()
    }
    
    private func setupAutoHide() {
        guard let window = window else { return }
        
        // Remove existing tracking area
        if let trackingArea = trackingArea {
            window.contentView?.removeTrackingArea(trackingArea)
        }
        
        if autoHide {
            // Create edge tracking area based on position
            let edgeRect = getEdgeTrackingRect()
            trackingArea = NSTrackingArea(
                rect: edgeRect,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            )
            
            if let trackingArea = trackingArea {
                window.contentView?.addTrackingArea(trackingArea)
            }
            
            // Start auto-hide timer
            startAutoHideTimer()
        } else {
            // Ensure dock is visible if auto-hide is disabled
            showDock()
        }
    }
    
    private func getEdgeTrackingRect() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        
        // Create a thin tracking area at the edge of the screen
        switch dockPosition {
        case .bottom:
            return NSRect(x: 0, y: 0, width: screen.frame.width, height: 5)
        case .top:
            return NSRect(x: 0, y: screen.frame.height - 5, width: screen.frame.width, height: 5)
        case .left:
            return NSRect(x: 0, y: 0, width: 5, height: screen.frame.height)
        case .right:
            return NSRect(x: screen.frame.width - 5, y: 0, width: 5, height: screen.frame.height)
        }
    }
    
    private func startAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.hideDock()
        }
    }
    
    private func hideDock() {
        guard autoHide && !isHidden else { return }
        
        isHidden = true
        guard let window = window else { return }
        
        let hiddenFrame = getHiddenFrame()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(hiddenFrame, display: true)
        }
    }
    
    private func showDock() {
        guard isHidden else { return }
        
        isHidden = false
        guard let window = window else { return }
        
        let visibleFrame = getVisibleFrame()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(visibleFrame, display: true)
        }
    }
    
    private func getHiddenFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        
        let dockHeight = getDockHeight()
        let dockWidth = getDockWidth(for: screen)
        let hideOffset: CGFloat = 2 // Small visible area
        
        switch dockPosition {
        case .bottom:
            return NSRect(
                x: 0,
                y: -dockHeight + hideOffset,
                width: screen.frame.width,
                height: dockHeight
            )
        case .top:
            return NSRect(
                x: 0,
                y: screen.frame.height - hideOffset,
                width: screen.frame.width,
                height: dockHeight
            )
        case .left:
            return NSRect(
                x: -dockWidth + hideOffset,
                y: 0,
                width: dockWidth,
                height: screen.frame.height
            )
        case .right:
            return NSRect(
                x: screen.frame.width - hideOffset,
                y: 0,
                width: dockWidth,
                height: screen.frame.height
            )
        }
    }
    
    private func getVisibleFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        
        let dockHeight = getDockHeight()
        let dockWidth = getDockWidth(for: screen)
        
        switch dockPosition {
        case .bottom:
            return NSRect(
                x: 0,
                y: 0,
                width: screen.frame.width,
                height: dockHeight
            )
        case .top:
            return NSRect(
                x: 0,
                y: screen.frame.height - dockHeight,
                width: screen.frame.width,
                height: dockHeight
            )
        case .left:
            return NSRect(
                x: 0,
                y: 0,
                width: dockWidth,
                height: screen.frame.height
            )
        case .right:
            return NSRect(
                x: screen.frame.width - dockWidth,
                y: 0,
                width: dockWidth,
                height: screen.frame.height
            )
        }
    }
    
    func mouseEntered(with event: NSEvent) {
        if autoHide {
            autoHideTimer?.invalidate()
            showDock()
        }
    }
    
    func mouseExited(with event: NSEvent) {
        if autoHide {
            // Check if mouse is still within dock bounds
            guard let window = window else { return }
            let mouseLocation = NSEvent.mouseLocation
            let windowFrame = window.frame
            
            if !NSPointInRect(mouseLocation, windowFrame) {
                startAutoHideTimer()
            }
        }
    }
    
    func resetAutoHideTimer() {
        autoHideTimer?.invalidate()
        if autoHide && !isHidden {
            startAutoHideTimer()
        }
    }
    
    deinit {
        autoHideTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // Custom window class to handle right-click events properly
    class CustomWindow: NSWindow {
        override func sendEvent(_ event: NSEvent) {
            if event.type == .rightMouseDown {
                // Pass right-click events to content view
                if let contentView = contentView {
                    // Convert to view coordinates
                    let locationInView = contentView.convert(event.locationInWindow, from: nil)
                    
                    // Post notification for SwiftUI views to handle
                    NotificationCenter.default.post(
                        name: NSView.rightMouseDownNotification,
                        object: contentView,
                        userInfo: ["location": NSValue(point: locationInView)]
                    )
                    
                    // Also pass to content view for normal handling
                    contentView.rightMouseDown(with: event)
                }
            } else {
                super.sendEvent(event)
            }
        }
        
        override var canBecomeKey: Bool {
            return true
        }
        
        override var canBecomeMain: Bool {
            return false
        }
    }
}

// Enhanced NSHostingView with better mouse tracking
class MouseTrackingHostingView<Content: View>: NSHostingView<Content> {
    weak var dockWindow: DockWindow?
    private var trackingArea: NSTrackingArea?
    
    init(rootView: Content, dockWindow: DockWindow) {
        self.dockWindow = dockWindow
        super.init(rootView: rootView)
        setupTrackingArea()
        
        // Enable right-click events
        self.window?.acceptsMouseMovedEvents = true
    }
    
    required init(rootView: Content) {
        super.init(rootView: rootView)
        setupTrackingArea()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupTrackingArea()
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setupTrackingArea()
    }
    
    // We don't need to override rightMouseDown here since the CustomWindow
    // already handles it through sendEvent and passes it to us
    
    override func mouseDown(with event: NSEvent) {
        // Handle normal clicks
        super.mouseDown(with: event)
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    private func setupTrackingArea() {
        // Remove existing tracking areas
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        // Add new tracking area for the entire view
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        
        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        dockWindow?.mouseEntered(with: event)
    }
    
    override func mouseExited(with event: NSEvent) {
        dockWindow?.mouseExited(with: event)
    }
    
    override func mouseMoved(with event: NSEvent) {
        // Track mouse movement for auto-hide
        if let dockWindow = dockWindow {
            dockWindow.resetAutoHideTimer()
        }
    }
}