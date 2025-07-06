import SwiftUI

@main
struct WinDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            TaskbarWindow()
                .environmentObject(RunningAppMonitor.shared)
        }
        // hide the normal title bar, keep it borderless
        .windowStyle(.hiddenTitleBar)
    }
}
