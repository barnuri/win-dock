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
    @State private var hidePreviewTask: DispatchWorkItem?

    // Computed properties for cleaner state management
    private var isActiveApp: Bool { 
        app.runningApplication?.isActive == true 
    }
    
    private var hasWindows: Bool { 
        app.windowCount > 0 || !app.windows.isEmpty 
    }
    
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
    
    private var backgroundStyle: some View {
        let fillColor: Color = {
            if isDragging {
                return Color.blue.opacity(0.4)
            } else if isActiveApp {
                return Color.blue.opacity(0.2)
            } else if isHovering {
                return Color.white.opacity(0.15)
            } else {
                return Color.clear
            }
        }()
        
        return RoundedRectangle(cornerRadius: 6)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isActiveApp ? Color.blue.opacity(0.3) : 
                        isHovering ? Color.white.opacity(0.2) : Color.clear, 
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isActiveApp ? Color.blue.opacity(0.2) : Color.clear,
                radius: isActiveApp ? 4 : 0,
                x: 0, y: 1
            )
            .animation(.easeOut(duration: 0.15), value: isActiveApp)
            .animation(.easeOut(duration: 0.1), value: isHovering)
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
                        
            // Notification badge
            if app.hasNotifications && app.notificationCount > 0 {
                notificationBadge
            }
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
    
    @ViewBuilder
    private var runningIndicator: some View {
        if isActiveApp {
            Rectangle()
                .fill(Color.blue)
                .frame(width: iconSize * 0.6, height: 2)
                .cornerRadius(1)
                .padding(.top, 2)
                .animation(.easeOut(duration: 0.2), value: isActiveApp)
        } else if app.isRunning || hasWindows {
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 4, height: 4)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                )
                .padding(.top, 0)
                .animation(.easeOut(duration: 0.15), value: hasWindows)
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
            if isActiveApp {
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
    
    private func handleMouseTracking(_ isInside: Bool) {
        isHovering = isInside
        
        // Cancel any pending hide task
        hidePreviewTask?.cancel()
        hidePreviewTask = nil
        
        if isInside {
            showWindowPreview = true
        } else {
            // Create a new hide task with delay
            let task = DispatchWorkItem {
                if !self.isHovering {
                    self.showWindowPreview = false
                }
            }
            hidePreviewTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
        }
    }
    
    private func handlePreviewMouseTracking(_ isInside: Bool) {
        // Cancel any pending hide task when entering preview
        if isInside {
            hidePreviewTask?.cancel()
            hidePreviewTask = nil
        } else {
            // Create a new hide task with delay when leaving preview
            let task = DispatchWorkItem {
                if !self.isHovering {
                    self.showWindowPreview = false
                }
            }
            hidePreviewTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
        }
    }
    
    private func handleTap() {
        if !app.isRunning {
            AppLogger.shared.info("AppDockItem handleTap for \(app.name), runningApplication is nil")
            appManager.activateApp(app)
            return
        }
        if app.windowCount > 1 {
            AppLogger.shared.info("AppDockItem handleTap for \(app.name), windowCount > 1")
            showWindowPreview = true
            return
        }
        if app.isHidden || app.isMinimized {
            AppLogger.shared.info("AppDockItem handleTap for \(app.name), isHidden or isMinimized")
            appManager.activateApp(app)
            return
        }
        AppLogger.shared.info("AppDockItem handleTap for \(app.name), isRunning is true and not Hidden Or Minimized")
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
