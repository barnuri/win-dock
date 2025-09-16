import SwiftUI
import AppKit

struct AppDockItem: View {
    let app: DockApp
    let iconSize: CGFloat
    let appManager: AppManager

    @AppStorage("showLabels") private var showLabels = false
    @State private var isHovering = false
    @State private var isDragging = false
    @State private var showWindowPreview = false
    @State private var hidePreviewTask: Task<Void, Never>?
    @State private var autoHidePreviewTask: Task<Void, Never>?
    @State private var previewDebounceTask: Task<Void, Never>?
    @State private var lastPreviewUpdate: Date = Date()
    private let previewDebounceDelay: TimeInterval = 0.15
      
    private var iconFrame: CGFloat { 
        iconSize * 0.7 
    }
    
    private var totalHeight: CGFloat { 
        showLabels ? 78 : 60 
    }

    var body: some View {
        VStack(spacing: 0) {
            iconSection
            runningIndicator
            if showLabels {
                appLabel
            }
        }
        .frame(width: 54, height: totalHeight)
        .background(backgroundStyle)
        .scaleEffect(isDragging ? 1.05 : isHovering ? 1.02 : 1.0)
        .opacity(isDragging ? 0.8 : 1.0)
        .contentShape(Rectangle())
        .background(
            MouseTrackingView { isInside in
                handleMouseTracking(isInside)
            }
        )
        .popover(isPresented: $showWindowPreview, arrowEdge: .top) {
            WindowPreviewView(app: app, appManager: appManager)
                .background(
                    MouseTrackingView { isInside in
                        handlePreviewMouseTracking(isInside)
                    }
                )
                .transition(.opacity.combined(with: .scale))
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
        .onDrag {
            createDragProvider()
        }
        .animation(.easeOut(duration: 0.15), value: isDragging)
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .help(toolTip)
    }
    
    // MARK: - View Components
    
    @State private var lastBackgroundState: (isDragging: Bool, isActive: Bool, isHovering: Bool) = (false, false, false)
    @State private var cachedBackgroundView: AnyView?
    
    private var backgroundStyle: some View {
        let currentState = (isDragging: isDragging, isActive: app.isActive, isHovering: isHovering)
        
        // Return cached view if state hasn't changed
        if currentState == lastBackgroundState, let cached = cachedBackgroundView {
            return cached
        }
        
        let fillColor: Color = {
            if isDragging {
                return Color.blue.opacity(0.4)
            } else if app.isActive {
                return Color.blue.opacity(0.2)
            } else if isHovering {
                return Color.white.opacity(0.15)
            } else {
                return Color.clear
            }
        }()
        
        let backgroundView = AnyView(
            RoundedRectangle(cornerRadius: 6)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            app.isActive ? Color.blue.opacity(0.3) : 
                            isHovering ? Color.white.opacity(0.2) : Color.clear, 
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: app.isActive ? Color.blue.opacity(0.2) : Color.clear,
                    radius: app.isActive ? 4 : 0,
                    x: 0, y: 1
                )
                .animation(.easeOut(duration: 0.1), value: app.isActive)
                .animation(.easeOut(duration: 0.08), value: isHovering)
        )
        
        // Cache the result - update state immediately since we're already on MainActor
        DispatchQueue.main.async {
            cachedBackgroundView = backgroundView
            lastBackgroundState = currentState
        }
        
        return backgroundView
    }
    
    private var iconSection: some View {
        ZStack {
            // App icon with brightness effect
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconFrame, height: iconFrame)
                    .brightness(isHovering ? 0.1 : 0.0)
                    .animation(.easeOut(duration: 0.1), value: isHovering)
            }
                        
            // Notification badge (top-right)
            if app.hasNotifications && app.notificationCount > 0 {
                notificationBadge
            }
            
            // Window count badge (bottom-right) - only show if more than 1 window
            // if app.windowCount > 1 {
            //     windowCountBadge
            // }
        }
    }
    
    private var notificationBadge: some View {
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
    
    private var windowCountBadge: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(
                            width: app.windowCount > 9 ? 20 : 16,
                            height: 14
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white, lineWidth: 1)
                        )
                    
                    Text("\(app.windowCount)")
                        .font(.system(
                            size: 9,
                            weight: .semibold,
                            design: .rounded
                        ))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .offset(x: 2, y: 2)
            }
        }
    }
    
    @ViewBuilder
    private var runningIndicator: some View {
        if app.isActive {
            Rectangle()
                .fill(Color.blue)
                .frame(width: iconSize * 0.6, height: 2)
                .cornerRadius(1)
                .padding(.top, 2)
                .animation(.easeOut(duration: 0.2), value: app.isActive)
        } else if app.hasWindows {
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 4, height: 4)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                )
                .padding(.top, 0)
                .animation(.easeOut(duration: 0.15), value: app.hasWindows)
        }
    }
    
    private var appLabel: some View {
        Text(app.name)
            .font(.system(size: 9))
            .foregroundColor(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 60)
            .padding(.top, 2)
    }
    
    // MARK: - Computed Properties
    
    private var toolTip: String {
        var tooltip = app.name
        if app.isRunning {
            if app.windowCount > 0 {
                tooltip += " (\(app.windowCount) window\(app.windowCount == 1 ? "" : "s"))"
            }
            if app.isActive {
                tooltip += " - Active"
            } else if app.runningApplication?.isHidden == true {
                tooltip += " - Hidden"
            }
        } else {
            tooltip += " - Click to launch"
        }
        return tooltip
    }
    
    // MARK: - Event Handlers
    
    @State private var mouseTrackingTask: Task<Void, Never>?
    
    private func handleMouseTracking(_ isInside: Bool) {
        // Cancel any previous tracking task
        mouseTrackingTask?.cancel()
        
        mouseTrackingTask = Task { @MainActor in
            // Small delay for debouncing
            try? await Task.sleep(for: .milliseconds(50))
            
            guard !Task.isCancelled else { return }
            
            let wasHovering = isHovering
            isHovering = isInside
            
            // Optimization: Only handle hover changes
            if wasHovering == isInside { return }
            
            if isInside {
                // Cancel any pending hide tasks
                hidePreviewTask?.cancel()
                autoHidePreviewTask?.cancel()
                
                // Debounce preview showing to prevent excessive updates
                previewDebounceTask?.cancel()
                
                // Show preview for all apps (single window, multiple windows, or not running)
                let now = Date()
                let timeSinceLastUpdate = now.timeIntervalSince(lastPreviewUpdate)
                
                // Only show preview if enough time has passed since last update
                if timeSinceLastUpdate >= previewDebounceDelay {
                    previewDebounceTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        
                        guard !Task.isCancelled, isHovering else { return }
                        
                        lastPreviewUpdate = Date()
                        showWindowPreview = true
                    }
                }
            } else {
                // Cancel preview debounce when leaving
                previewDebounceTask?.cancel()
                
                // Create a new hide task with optimized delay
                hidePreviewTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    
                    guard !Task.isCancelled, !isHovering else { return }
                    
                    withAnimation(.easeOut(duration: 0.1)) {
                        showWindowPreview = false
                    }
                }
            }
        }
    }
    
    private func handlePreviewMouseTracking(_ isInside: Bool) {
        if isInside {
            // Cancel any pending hide task when entering preview
            hidePreviewTask?.cancel()
            hidePreviewTask = nil
            // Also cancel auto-hide when mouse is over preview
            autoHidePreviewTask?.cancel()
            autoHidePreviewTask = nil
        } else {
            // Only hide if we're also not hovering over the dock item
            // Add a delay to prevent flicker when moving between dock item and preview
            hidePreviewTask = Task { @MainActor in
                // Increased delay to allow smooth transition between dock item and preview
                try? await Task.sleep(for: .milliseconds(500))
                
                guard !Task.isCancelled, !isHovering else { return }
                
                // Double-check both hover states before hiding
                withAnimation(.easeOut(duration: 0.2)) {
                    showWindowPreview = false
                }
            }
        }
    }
    
    private func handleTap() {
        if !app.isRunning {
            AppLogger.shared.info("AppDockItem handleTap for \(app.name), runningApplication is nil")
            appManager.activateApp(app)
            return
        }
        
        // If app has multiple windows, show preview
        if app.windowCount > 1 {
            AppLogger.shared.info("AppDockItem handleTap for \(app.name), windowCount > 1")
            showWindowPreview = true
            return
        }

        // If app is not active, activate it (brings windows to front)
        if !app.isActive {
            AppLogger.shared.info("AppDockItem handleTap for \(app.name), not active - activating")
            appManager.activateApp(app)
            return
        }
        
        // If app is hidden or minimized, restore it
        if app.isHidden || app.isMinimized {
            AppLogger.shared.info("AppDockItem handleTap for \(app.name), isHidden or isMinimized")
            appManager.activateApp(app)
            return
        }
        
        // App is active and visible, minimize/hide it
        AppLogger.shared.info("AppDockItem handleTap for \(app.name), isActive and visible - hiding")
        appManager.hideApp(app)
    }
    
    private func createDragProvider() -> NSItemProvider {
        isDragging = true
        
        let itemProvider = NSItemProvider()
        
        // Register the app's bundle identifier as drag data
        itemProvider.registerDataRepresentation(
            forTypeIdentifier: "public.plain-text", 
            visibility: .all
        ) { completion in
            let data = self.app.bundleIdentifier.data(using: .utf8) ?? Data()
            completion(data, nil)
            return nil
        }
        
        // Register app info as a custom type for better drag handling
        itemProvider.registerDataRepresentation(
            forTypeIdentifier: "com.windock.app-item",
            visibility: .all
        ) { completion in
            let appInfo = [
                "bundleIdentifier": self.app.bundleIdentifier,
                "name": self.app.name,
                "url": self.app.url?.absoluteString ?? ""
            ]
            
            do {
                let data = try JSONSerialization.data(withJSONObject: appInfo)
                completion(data, nil)
            } catch {
                completion(nil, error)
            }
            return nil
        }
        
        // Listen for drag end notification to reset state
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DragEnded"),
            object: nil,
            queue: .main
        ) { _ in
            self.isDragging = false
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("DragEnded"), object: nil)
        }
        
        return itemProvider
    }
}

// MARK: - Mouse Tracking Helper

struct MouseTrackingView: NSViewRepresentable {
    let onMouseChange: (Bool) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = TrackingNSView()
        view.onMouseChange = onMouseChange
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let trackingView = nsView as? TrackingNSView {
            trackingView.onMouseChange = onMouseChange
        }
    }
}

class TrackingNSView: NSView {
    var onMouseChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        
        addTrackingArea(area)
        trackingArea = area
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouseChange?(true)
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseChange?(false)
    }
}
