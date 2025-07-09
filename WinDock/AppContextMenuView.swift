import SwiftUI
import AppKit

struct AppContextMenuView: View {
    let app: DockApp
    let appManager: AppManager
    
    var body: some View {
        Group {
            if app.isRunning {
                Button("Show Windows Preview") {
                    AppMenuHandler.shared.appManager = appManager
                    AppMenuHandler.shared.showWindowsPreviewPanel(for: app)
                }
                Button("Show All Windows") {
                    appManager.showAllWindows(for: app)
                }
                if app.windows.count > 0 {
                    Divider()
                    ForEach(Array(app.windows.enumerated()), id: \.element.windowID) { index, window in
                        Button(window.title.isEmpty ? "Window \(index + 1)" : window.title) {
                            AppMenuHandler.shared.focusSpecificWindow(windowID: window.windowID, app: app)
                        }
                    }
                    Divider()
                    Button("Close All Windows") {
                        AppMenuHandler.shared.closeAllWindowsForApp(app)
                    }
                }
                Divider()
                Button("Hide") {
                    appManager.hideApp(app)
                }
                Button("Quit") {
                    appManager.quitApp(app)
                }
            } else {
                Button("Open") {
                    appManager.launchApp(app)
                }
            }
            Divider()
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
}
