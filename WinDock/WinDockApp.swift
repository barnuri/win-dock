import SwiftUI
import AppKit

@main
struct WinDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
        // Removed MenuBarExtra to avoid duplicate menu in the top bar
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var dockWindow: DockWindow?
    var statusBarItem: NSStatusItem?
    var settingsWindowObserver: NSObjectProtocol?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep app in dock but don't show in dock switcher
        NSApp.setActivationPolicy(.regular)

        // Create status bar item for easy access
        setupStatusBarItem()

        // Create and show the dock window
        dockWindow = DockWindow()
        dockWindow?.show()

        // Monitor for settings window closing
        setupSettingsWindowObserver()
        // Do not switch to .accessory immediately; keep .regular so UI is visible
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    private func setupSettingsWindowObserver() {
        settingsWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow,
               window.title.contains("Settings") || window.title.contains("Preferences") {
                // Settings window is closing, return to accessory mode
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
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
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsMenu), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit Win Dock", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusBarItem?.menu = menu
    }
    
    @objc private func statusBarItemClicked() {
        // Show context menu
    }
    
    @objc func openSettingsMenu() {
        openSettings()
    }

    @objc func openSettings() {
        // Ensure we're in regular mode to show windows
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // Try to bring existing settings window to front first
        for window in NSApp.windows {
            if window.title.contains("Settings") || window.title.contains("Preferences") {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                return
            }
        }
        
        // If no existing window, create new one
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if #available(macOS 14.0, *) {
                if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            } else {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
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
