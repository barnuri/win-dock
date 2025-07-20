import SwiftUI
import AppKit

class AboutWindow: NSWindow {
    static func showAboutWindow() {
        // Check if about window already exists
        if let existingWindow = NSApp.windows.first(where: { $0.title == "About Win Dock" }) {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create a new about window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        // Configure window properties
        window.title = "About Win Dock"
        window.center()
        window.isReleasedWhenClosed = false
        
        // Create the SwiftUI view
        let aboutView = AboutView()
        let hostingController = NSHostingController(rootView: aboutView)
        
        // Set the view controller
        window.contentViewController = hostingController
        
        // Show the window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        AppLogger.shared.info("About window opened")
    }
}
