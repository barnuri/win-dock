import SwiftUI
import AppKit

struct WindowsTaskbarIcon: View {
    let app: DockApp
    let isHovered: Bool
    let iconSize: CGFloat
    let appManager: AppManager

    @AppStorage("showLabels") private var showLabels = false
    @State private var showPreview = false
    @State private var previewPosition: CGPoint = .zero
    @State private var isDragging = false
    @State private var dragOffset = CGSize.zero
    @State private var hoverTimer: Timer?
    @State private var isIconHovered = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Simple background without highlighting
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.clear)
                    .frame(width: 48, height: 40)
                
                // App icon
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize * 0.7, height: iconSize * 0.7)
                        .scaleEffect(isDragging ? 0.9 : (isIconHovered ? 1.2 : 1.0))
                        .opacity(isDragging ? 0.7 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isIconHovered)
                        .animation(.easeInOut(duration: 0.15), value: isDragging)
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
            
            // Running indicator (line at bottom)
            Rectangle()
                .fill(runningIndicatorColor)
                .frame(width: runningIndicatorWidth, height: 3)
                .cornerRadius(1.5)
                .padding(.top, 2)
                .opacity(app.isRunning ? 1.0 : 0.0)
            
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
        .offset(dragOffset)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .onHover { hovering in
            // Update icon hover state for animations - keep it simple and stable
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isIconHovered = hovering && !isDragging
            }
            
            hoverTimer?.invalidate()
            
            if hovering && app.isRunning && app.windowCount > 0 && !isDragging {
                // Longer delay to prevent flicker and immediate opening/closing
                hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
                    if !isDragging { // Double check we're not dragging
                        showPreview = true
                    }
                }
            } else if !hovering {
                // Hide preview and reset icon size when mouse leaves
                if showPreview {
                    hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
                        showPreview = false
                    }
                }
            }
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
        .highPriorityGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        showPreview = false // Hide preview when dragging
                        hoverTimer?.invalidate() // Cancel any pending preview
                        
                        // Update icon hover state when dragging starts
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isIconHovered = false
                        }
                    }
                    dragOffset = value.translation
                }
                .onEnded { value in
                    isDragging = false
                    dragOffset = .zero
                    handleDrop(at: value.location)
                }
        )
        .popover(isPresented: $showPreview, attachmentAnchor: .point(.center), arrowEdge: .top) {
            WindowPreviewView(app: app, appManager: appManager)
                .onHover { hovering in
                    // Keep the preview open when hovering over it
                    hoverTimer?.invalidate()
                    if !hovering {
                        // Only close after a delay when mouse leaves the preview
                        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                            showPreview = false
                        }
                    }
                }
        }
        .help(toolTip)
    }

    private var runningIndicatorColor: Color {
        if app.runningApplication?.isActive == true {
            return Color.accentColor
        }
        return Color.accentColor.opacity(0.7)
    }
    
    private var runningIndicatorWidth: CGFloat {
        if app.runningApplication?.isActive == true {
            return 24
        }
        return 16
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
    
    private func handleDrop(at location: CGPoint) {
        // Find the target position in the dock
        if let window = NSApp.windows.first(where: { $0.contentView?.subviews.contains { $0 is NSHostingView<DockView> } != nil }) {
            // Convert global coordinates to window coordinates
            let windowLocation = window.convertPoint(fromScreen: location)
            
            // Notify the dock view about the drop
            NotificationCenter.default.post(
                name: NSNotification.Name("DockIconDropped"),
                object: nil,
                userInfo: [
                    "app": app,
                    "location": NSValue(point: windowLocation)
                ]
            )
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
}
