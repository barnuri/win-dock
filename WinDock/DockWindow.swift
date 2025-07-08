//
//  DockWindow.swift
//  WinDock
//
//  Created by GitHub Copilot on 08/07/2025.
//

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
    
    func show() {
        guard let screen = NSScreen.main else { return }
        
        let windowRect = NSRect(
            x: 0,
            y: 0,
            width: getDockWidth(for: screen),
            height: getDockHeight()
        )
        
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        guard let window = window else { return }
        
        // Configure window properties - ensure it's always on top
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.canHide = false
        
        // Configure collection behavior based on settings
        var collectionBehavior: NSWindow.CollectionBehavior = [.stationary, .ignoresCycle]
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
            return dockSize.iconSize + 24 // Thinner padding for Windows 11 style
        case .left, .right:
            return 200 // Fixed height for vertical docks
        }
    }
    
    private func getDockWidth(for screen: NSScreen) -> CGFloat {
        switch dockPosition {
        case .bottom, .top:
            return screen.frame.width
        case .left, .right:
            return dockSize.iconSize + 24 // Thinner padding for vertical docks
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
            // Create tracking area for mouse enter/exit
            trackingArea = NSTrackingArea(
                rect: window.contentView?.bounds ?? .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
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
    
    private func startAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.hideDock()
        }
    }
    
    private func hideDock() {
        guard autoHide && !isHidden else { return }
        
        isHidden = true
        guard let window = window else { return }
        
        let hiddenFrame = getHiddenFrame()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
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
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(visibleFrame, display: true)
        }
    }
    
    private func getHiddenFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        
        let dockHeight = getDockHeight()
        let dockWidth = getDockWidth(for: screen)
        let hideOffset: CGFloat = 5 // Small visible area to trigger mouse enter
        
        switch dockPosition {
        case .bottom:
            return NSRect(
                x: screen.visibleFrame.minX,
                y: screen.visibleFrame.minY - dockHeight + hideOffset,
                width: screen.visibleFrame.width,
                height: dockHeight
            )
        case .top:
            return NSRect(
                x: screen.visibleFrame.minX,
                y: screen.visibleFrame.maxY - hideOffset,
                width: screen.visibleFrame.width,
                height: dockHeight
            )
        case .left:
            return NSRect(
                x: screen.visibleFrame.minX - dockWidth + hideOffset,
                y: screen.visibleFrame.minY,
                width: dockWidth,
                height: screen.visibleFrame.height
            )
        case .right:
            return NSRect(
                x: screen.visibleFrame.maxX - hideOffset,
                y: screen.visibleFrame.minY,
                width: dockWidth,
                height: screen.visibleFrame.height
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
                x: screen.visibleFrame.minX,
                y: screen.visibleFrame.minY,
                width: screen.visibleFrame.width,
                height: dockHeight
            )
        case .top:
            return NSRect(
                x: screen.visibleFrame.minX,
                y: screen.visibleFrame.maxY - dockHeight,
                width: screen.visibleFrame.width,
                height: dockHeight
            )
        case .left:
            return NSRect(
                x: screen.visibleFrame.minX,
                y: screen.visibleFrame.minY,
                width: dockWidth,
                height: screen.visibleFrame.height
            )
        case .right:
            return NSRect(
                x: screen.visibleFrame.maxX - dockWidth,
                y: screen.visibleFrame.minY,
                width: dockWidth,
                height: screen.visibleFrame.height
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
            startAutoHideTimer()
        }
    }
    
    deinit {
        autoHideTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

// Custom NSHostingView that can track mouse events for auto-hide functionality
class MouseTrackingHostingView<Content: View>: NSHostingView<Content> {
    weak var dockWindow: DockWindow?
    
    init(rootView: Content, dockWindow: DockWindow) {
        self.dockWindow = dockWindow
        super.init(rootView: rootView)
        setupTrackingArea()
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
    
    override func rightMouseDown(with event: NSEvent) {
        // Show menu bar when right clicking empty space
        activateAppTemporarily()
        super.rightMouseDown(with: event)
    }
    
    override func mouseDown(with event: NSEvent) {
        // Activate app on left click too
        if event.clickCount == 1 {
            activateAppTemporarily()
        }
        super.mouseDown(with: event)
    }
    
    private func activateAppTemporarily() {
        // Temporarily activate the app to show menu bar
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // Return to accessory mode after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    private func setupTrackingArea() {
        // Remove existing tracking areas
        trackingAreas.forEach { removeTrackingArea($0) }
        
        // Add new tracking area
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        dockWindow?.mouseEntered(with: event)
    }
    
    override func mouseExited(with event: NSEvent) {
        dockWindow?.mouseExited(with: event)
    }
}
