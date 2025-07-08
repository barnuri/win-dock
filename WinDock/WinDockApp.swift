//
//  WinDockApp.swift
//  WinDock
//
//  Created by  bar nuri on 06/07/2025.
//

import SwiftUI
import AppKit

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
    var dockWindow: DockWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from dock and menu bar for a cleaner experience
        NSApp.setActivationPolicy(.accessory)
        
        // Create and show the dock window
        dockWindow = DockWindow()
        dockWindow?.show()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
