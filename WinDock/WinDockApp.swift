//
//  WinDockApp.swift
//  WinDock
//
//  Created by  bar nuri on 0    @objc func openSettings() {
        // Make app active temporarily to show settings
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        
        // Return to accessory mode after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.setActivationPolicy(.accessory)
        }
    }mport SwiftUI
import AppKit

@main
struct WinDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
        
        MenuBarExtra("Win Dock", systemImage: "dock.rectangle") {
            VStack {
                Button("Settings...") {
                    appDelegate.openSettings()
                }
                
                Divider()
                
                Button("Quit Win Dock") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var dockWindow: DockWindow?
    var statusBarItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep app in dock but don't show in dock switcher
        NSApp.setActivationPolicy(.regular)
        
        // Create status bar item for easy access
        setupStatusBarItem()
        
        // Create and show the dock window
        dockWindow = DockWindow()
        dockWindow?.show()
        
        // Hide the app from dock after setup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }
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
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Win Dock", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusBarItem?.menu = menu
    }
    
    @objc private func statusBarItemClicked() {
        // Show context menu
    }
    
    @objc private func openSettings() {
        // Make app active temporarily to show settings
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        
        // Return to accessory mode after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
