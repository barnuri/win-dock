import SwiftUI
import AppKit

struct AppContextMenuView: View {
    let app: DockApp
    let appManager: AppManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuContent
            Divider()
            pinSection
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if app.isRunning {
            if app.windowCount > 1 {
                Button("Show Window Previews") {
                    // This would need to be handled by the parent view
                    // For now, just show all windows
                    appManager.showAllWindows(for: app)
                }
            }
            
            Button("Show All Windows") {
                appManager.showAllWindows(for: app)
            }
            if app.windows.count > 0 {
                Divider()
                ForEach(Array(app.windows.enumerated()), id: \.element.windowID) { index, window in
                    Button(window.title.isEmpty ? "Window \(index + 1)" : window.title) {
                        appManager.focusWindow(windowID: window.windowID, app: app)
                    }
                }
                Divider()
                Button("Close All Windows") {
                    appManager.closeAllWindows(for: app)
                }
            }
            Divider()
            Button("Hide") {
                appManager.hideApp(app)
            }
            Button("Hide Others") {
                appManager.hideOtherApps(except: app)
            }
            Button("Quit") {
                appManager.quitApp(app)
            }
        } else {
            Button("Open") {
                appManager.launchApp(app)
            }
        }
    }

    @ViewBuilder
    private var pinSection: some View {
        if app.isPinned {
            Button("Unpin from taskbar") {
                appManager.unpinApp(app)
            }
        } else {
            Button("Pin to taskbar") {
                appManager.pinApp(app)
            }
        }
    }
}
