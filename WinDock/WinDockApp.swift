import SwiftUI
import AppKit

import Foundation
import Darwin

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
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var dockWindows: [DockWindow] = []
    var statusBarItem: NSStatusItem?
    var settingsWindowObserver: NSObjectProtocol?
    var dockPosition: DockPosition = .bottom
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setGlobalErrorHandlers()
        setupStatusBarItem()
        setupDockWindowsForAllScreens()
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersDidChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
   
    private func setupStatusBarItem() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let statusButton = statusBarItem?.button {
            statusButton.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Win Dock")
            statusButton.action = #selector(statusBarItemClicked)
            statusButton.target = self
        }

        // Create menu for status bar item
        let menu = NSMenu()
        // Add app name at the top, disabled
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Win Dock"
        let appNameItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        appNameItem.isEnabled = false
        menu.addItem(appNameItem)
        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsMenu), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit Win Dock", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

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

        statusBarItem?.menu = menu
    }
    
    @objc private func statusBarItemClicked() {
        // Show dock window on all displays and bring to front
        for dockWindow in dockWindows {
            dockWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            dockWindow.level = .floating
            dockWindow.orderFrontRegardless()
            dockWindow.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // Centralized frame calculation for dock position
    func dockFrame(for position: DockPosition, screen: NSScreen) -> NSRect {
        let screenFrame = screen.visibleFrame
        let dockHeight: CGFloat = 64
        let dockWidth: CGFloat = min(600, screenFrame.width * 0.6)
        switch position {
        case .bottom:
            return NSRect(
                x: screenFrame.midX - dockWidth / 2,
                y: screenFrame.minY,
                width: dockWidth,
                height: dockHeight
            )
        case .top:
            return NSRect(
                x: screenFrame.midX - dockWidth / 2,
                y: screenFrame.maxY - dockHeight,
                width: dockWidth,
                height: dockHeight
            )
        case .left:
            return NSRect(
                x: screenFrame.minX,
                y: screenFrame.midY - dockWidth / 2,
                width: dockHeight,
                height: dockWidth
            )
        case .right:
            return NSRect(
                x: screenFrame.maxX - dockHeight,
                y: screenFrame.midY - dockWidth / 2,
                width: dockHeight,
                height: dockWidth
            )
        }
    }

    private func setupDockWindowsForAllScreens() {
        // Remove old windows
        for window in dockWindows {
            window.close()
        }
        dockWindows.removeAll()
        // Create a DockWindow for each screen
        for screen in NSScreen.screens {
            let dockWindow = DockWindow()
            let frame = dockFrame(for: dockPosition, screen: screen)
            dockWindow.setFrame(frame, display: true)
            dockWindow.show()
            dockWindows.append(dockWindow)
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
    
    @objc func openSettingsMenu() {
        openSettings()
    }

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        for window in NSApp.windows {
            if window.title.contains("Settings") || window.title.contains("Preferences") {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                return
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if #available(macOS 14.0, *) {
                if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                    _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            } else {
                _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    deinit {
        if let observer = settingsWindowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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