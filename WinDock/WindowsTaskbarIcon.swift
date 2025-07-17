import SwiftUI
import AppKit

struct WindowsTaskbarIcon: View {
    let app: DockApp
    let iconSize: CGFloat
    let appManager: AppManager

    @AppStorage("showLabels") private var showLabels = false
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Simple app icon without hover effects
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize * 0.7, height: iconSize * 0.7)
                }
                
                // Window count indicators (small dots at bottom)
                if app.windowCount > 1 {
                    HStack(spacing: 2) {
                        ForEach(0..<min(app.windowCount, 4), id: \.self) { _ in
                            Circle()
                                .fill(Color.primary.opacity(0.8))
                                .frame(width: 3, height: 3)
                        }
                        if app.windowCount > 4 {
                            Text("+")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.primary)
                        }
                    }
                    .offset(y: 16)
                }
            }
            
            // App label (optional)
            if showLabels {
                Text(app.name)
                    .font(.system(size: 9))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 60)
                    .padding(.top, 2)
            }
        }
        .frame(width: 54, height: showLabels ? 72 : 54)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    app.runningApplication?.isActive == true ? 
                        Color.blue.opacity(0.3) : 
                        (isHovering ? Color.gray.opacity(0.3) : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            handleTap()
        }
        .contextMenu {
            AppContextMenuView(app: app, appManager: appManager)
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { _ in
                if app.isRunning {
                    appManager.launchNewInstance(app)
                }
            }
        )
        .help(toolTip)
    }
    
    private var toolTip: String {
        var tooltip = app.name
        if app.isRunning {
            if app.windowCount > 0 {
                tooltip += " (\(app.windowCount) window\(app.windowCount == 1 ? "" : "s"))"
            }
            if app.runningApplication?.isActive == true {
                tooltip += " - Active"
            } else if app.runningApplication?.isHidden == true {
                tooltip += " - Hidden"
            }
        } else {
            tooltip += " - Click to launch"
        }
        return tooltip
    }
    
    
    private func handleTap() {
        AppLogger.shared.info("WindowsTaskbarIcon handleTap for \(app.name)")
        
        if app.isRunning {
            if let runningApp = app.runningApplication {
                if runningApp.isActive && app.windowCount <= 1 {
                    // If single window app is already active, minimize it
                    appManager.hideApp(app)
                } else {
                    // Always try to activate and bring to front
                    appManager.activateApp(app)
                }
            }
        } else {
            // Launch the app
            appManager.activateApp(app)
        }
    }
}
