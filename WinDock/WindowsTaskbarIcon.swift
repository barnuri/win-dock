import SwiftUI
import AppKit

struct WindowsTaskbarIcon: View {
    let app: DockApp
    let iconSize: CGFloat
    let appManager: AppManager

    @AppStorage("showLabels") private var showLabels = false
    @State private var isHovering = false
    @State private var isDragging = false
    @State private var showWindowPreview = false
    @State private var hoverTimer: Timer?

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
                
                // Notification badge (top right corner)
                if app.hasNotifications && app.notificationCount > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: app.notificationCount > 9 ? 18 : 16, height: app.notificationCount > 9 ? 18 : 16)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 1.5)
                                    )
                                
                                Text(app.notificationCount > 99 ? "99+" : "\(app.notificationCount)")
                                    .font(.system(size: app.notificationCount > 9 ? 7 : 8, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                            .offset(x: 2, y: -2)
                        }
                        Spacer()
                    }
                }
            }
            
            // Running indicator underline (Windows 11 style)
            if app.isRunning {
                Rectangle()
                    .fill(app.runningApplication?.isActive == true ? 
                          Color.accentColor : 
                          Color(NSColor.controlAccentColor).opacity(0.7))
                    .frame(width: iconSize * 0.4, height: 3)
                    .cornerRadius(1.5)
                    .padding(.top, 1)
                    .animation(.easeInOut(duration: 0.2), value: app.runningApplication?.isActive)
            } else {
                // Placeholder to maintain consistent spacing
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: iconSize * 0.4, height: 3)
                    .padding(.top, 1)
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
        .frame(width: 54, height: showLabels ? 78 : 60) // Increased height to accommodate underline
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    isDragging ? Color.blue.opacity(0.5) :
                    app.runningApplication?.isActive == true ? 
                        Color.blue.opacity(0.3) : 
                        (isHovering ? Color.gray.opacity(0.3) : Color.clear)
                )
        )
        .scaleEffect(isDragging ? 1.1 : 1.0)
        .opacity(isDragging ? 0.8 : 1.0)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering && app.isRunning {
                // Cancel any existing timer to prevent multiple timers
                hoverTimer?.invalidate()
                hoverTimer = nil
                
                // Start new timer for preview delay - reduced delay for better responsiveness
                hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak hoverTimer] _ in
                    // Only show if this timer wasn't cancelled and still hovering
                    if hoverTimer != nil && isHovering {
                        showWindowPreview = true
                    }
                }
            } else {
                // Cancel timer and hide preview immediately
                hoverTimer?.invalidate()
                hoverTimer = nil
                showWindowPreview = false
            }
        }
        .popover(isPresented: $showWindowPreview, arrowEdge: .top) {
            WindowPreviewView(app: app, appManager: appManager)
                .onDisappear {
                    // Clean up timer when popover is dismissed
                    hoverTimer?.invalidate()
                    hoverTimer = nil
                }
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
        .onDrag {
            isDragging = true
            
            // Reset dragging state when drag ends
            let dragEndObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("DragEnded"),
                object: nil,
                queue: .main
            ) { _ in
                isDragging = false
            }
            
            // Clean up after a timeout as a fallback
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                NotificationCenter.default.removeObserver(dragEndObserver)
                if isDragging {
                    isDragging = false
                }
            }
            
            // Create item provider with the bundle identifier as plain text
            let itemProvider = NSItemProvider()
            itemProvider.registerDataRepresentation(forTypeIdentifier: "public.plain-text", visibility: .all) { completion in
                let data = app.bundleIdentifier.data(using: .utf8) ?? Data()
                completion(data, nil)
                return nil
            }
            return itemProvider
        }
        .animation(.easeInOut(duration: 0.2), value: isDragging)
        .help(toolTip)
        .onDisappear {
            // Clean up timer when view disappears
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
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
