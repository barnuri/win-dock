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
        let content = createMainContent()
        return content
    }
    
    private func createMainContent() -> some View {
        let iconFrame = iconSize * 0.7
        let totalHeight: CGFloat = showLabels ? 78 : 60
        
        return VStack(spacing: 0) {
            createIconSection(iconFrame: iconFrame)
            createRunningIndicator()
            
            if showLabels {
                createAppLabel()
            }
        }
        .frame(width: 54, height: totalHeight)
        .background(createBackgroundStyle())
        .scaleEffect(isDragging ? 1.1 : 1.0)
        .opacity(isDragging ? 0.8 : 1.0)
        .contentShape(Rectangle())
        .onHover(perform: handleHover)
        .popover(isPresented: $showWindowPreview, arrowEdge: .top) {
            WindowPreviewView(app: app, appManager: appManager)
                .onDisappear {
                    hoverTimer?.invalidate()
                    hoverTimer = nil
                }
        }
        .onTapGesture(perform: handleTap)
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
        .onDrag(createDragProvider)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
        .help(toolTip)
        .onDisappear {
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
    }
    
    private func createBackgroundStyle() -> some View {
        let isActiveApp = app.runningApplication?.isActive == true
        let fillColor: Color = {
            if isDragging {
                return Color.blue.opacity(0.5)
            } else if isActiveApp {
                return Color.accentColor.opacity(0.25)
            } else if isHovering {
                return Color.white.opacity(0.2)
            } else {
                return Color.clear
            }
        }()
        
        let strokeColor: Color = {
            if isDragging {
                return Color.blue.opacity(0.7)
            } else if isActiveApp {
                return Color.accentColor.opacity(0.4)
            } else if isHovering {
                return Color.white.opacity(0.5)
            } else {
                return Color.clear
            }
        }()
        
        return RoundedRectangle(cornerRadius: 4)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(strokeColor, lineWidth: (isHovering || isActiveApp) ? 1 : 0)
            )
    }
    
    private func createIconSection(iconFrame: CGFloat) -> some View {
        ZStack {
            // App icon
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconFrame, height: iconFrame)
            }
            
            // Window count indicators
            if app.windowCount > 1 {
                createWindowCountIndicators()
            }
            
            // Notification badge
            if app.hasNotifications && app.notificationCount > 0 {
                createNotificationBadge()
            }
        }
    }
    
    private func createWindowCountIndicators() -> some View {
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
    
    private func createNotificationBadge() -> some View {
        VStack {
            HStack {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(
                            width: app.notificationCount > 9 ? 18 : 16,
                            height: app.notificationCount > 9 ? 18 : 16
                        )
                        .overlay(
                            Circle().stroke(Color.white, lineWidth: 1.5)
                        )
                    
                    Text(app.notificationCount > 99 ? "99+" : "\(app.notificationCount)")
                        .font(.system(
                            size: app.notificationCount > 9 ? 7 : 8,
                            weight: .bold,
                            design: .rounded
                        ))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .offset(x: 2, y: -2)
            }
            Spacer()
        }
    }
    
    @ViewBuilder
    private func createRunningIndicator() -> some View {
        Rectangle()
            .fill(
                app.isRunning ? (
                    app.runningApplication?.isActive == true ?
                    Color.accentColor :
                    Color(NSColor.controlAccentColor).opacity(0.7)
                ) : Color.clear
            )
            .frame(width: iconSize * 0.4, height: 3)
            .cornerRadius(app.isRunning ? 1.5 : 0)
            .padding(.top, 1)
            .animation(.easeInOut(duration: 0.2), value: app.runningApplication?.isActive)
    }
    
    private func createAppLabel() -> some View {
        Text(app.name)
            .font(.system(size: 9))
            .foregroundColor(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 60)
            .padding(.top, 2)
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
    
    private func handleHover(_ hovering: Bool) {
        isHovering = hovering
        
        if hovering && app.isRunning && app.windowCount > 0 {
            hoverTimer?.invalidate()
            hoverTimer = nil
            
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
                if self.isHovering {
                    self.showWindowPreview = true
                }
            }
        } else {
            hoverTimer?.invalidate()
            hoverTimer = nil
            showWindowPreview = false
        }
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
    
    private func createDragProvider() -> NSItemProvider {
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
}
