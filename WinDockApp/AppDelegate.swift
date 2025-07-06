import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The first window is created by SwiftUI; we adjust its style in TaskbarWindowConfigurator.
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // keep running even if no windows (so user can relaunch)
        false
    }
}
