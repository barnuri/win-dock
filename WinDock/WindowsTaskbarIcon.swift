import SwiftUI
import AppKit

struct WindowsTaskbarIcon: View {
    let app: DockApp
    let iconSize: CGFloat
    let appManager: AppManager

    @AppStorage("showLabels") private var showLabels = false
    @State private var showPreview = false
    @State private var isDragging = false
    @State private var dragOffset = CGSize.zero
    @State private var hoverTimer: Timer?
    @State private var isIconHovered = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Windows 11 style highlight on hover
                RoundedRectangle(cornerRadius: 4)
                    .fill(isIconHovered && !isDragging ? 
                          Color(NSColor.controlBackgroundColor).opacity(0.5) : 
                          Color.clear)
                    .frame(width: 44, height: 36)
                
                // App icon - no scaling on hover (Windows 11 style)
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize * 0.7, height: iconSize * 0.7)
                        .scaleEffect(isDragging ? 0.9 : 1.0)
                        .opacity(isDragging ? 0.7 : 1.0)
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
        .offset(dragOffset)
        .contentShape(Rectangle())
        // Improved hover handling with simplified logic
        .onHover { hovering in
            // Don't update hover state during drag
            if isDragging {
                return
            }
            
            // Cancel any pending timers
            hoverTimer?.invalidate()
            
            if hovering {
                // Animate hover state
                withAnimation(.easeInOut(duration: 0.15)) {
                    isIconHovered = true
                }
                
                // Handle window preview if applicable
                if app.isRunning && app.windowCount > 0 {
                    AppLogger.shared.info("Scheduling preview for \(app.name)")
                    hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { _ in
                        if !isDragging && isIconHovered {
                            AppLogger.shared.info("Showing preview for \(app.name)")
                            showPreview = true
                        }
                    }
                }
            } else {
                // Mouse exited
                withAnimation(.easeInOut(duration: 0.15)) {
                    isIconHovered = false
                }
                
                // Hide window preview with slight delay
                if showPreview {
                    hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                        showPreview = false
                    }
                }
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
        .gesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        showPreview = false
                        hoverTimer?.invalidate()
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isIconHovered = false
                        }
                    }
                    dragOffset = value.translation
                }
                .onEnded { value in
                    // Save the current value before resetting
                    let finalLocation = value.location
                    dragOffset = .zero
                    
                    // Wait briefly for animation to complete, then notify about drop
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        handleDrop(at: finalLocation)
                        
                        // Reset dragging state after drop is fully handled
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isDragging = false
                        }
                    }
                }
        )
        .popover(isPresented: $showPreview, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            WindowPreviewView(app: app, appManager: appManager)
                .frame(width: 280)
                .onAppear {
                    AppLogger.shared.info("Showing preview for \(app.name)")
                }
                .onDisappear {
                    AppLogger.shared.info("Preview dismissed for \(app.name)")
                }
        }
        .help(toolTip)
    }
    
    // No indicators needed - removed blue line as requested

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
        AppLogger.shared.info("WindowsTaskbarIcon handleDrop at \(location)")
        
        // Forcefully post notification to all windows, letting them decide if they should handle it
        let windowLocation = location
        
        // Print all windows for debugging
        AppLogger.shared.info("All windows: \(NSApp.windows.map { $0.className })")
        
        // Notify the dock view about the drop
        NotificationCenter.default.post(
            name: NSNotification.Name("DockIconDropped"),
            object: nil,
            userInfo: [
                "app": app,
                "location": NSValue(point: windowLocation)
            ]
        )
        
        // Force an update to the app manager to reflect any changes
        appManager.updateDockAppsIfNeeded()
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
