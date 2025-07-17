import SwiftUI
import AppKit

struct DockView: View {
    @StateObject private var appManager = AppManager()
    @State private var showingPreview = false
    @State private var previewWindow: NSWindow?
    @State private var draggedApp: DockApp?
    @State private var showStartMenu = false
    @State private var dropInsertionIndex: Int?
    @AppStorage("dockPosition") private var dockPosition: DockPosition = .bottom
    @AppStorage("dockSize") private var dockSize: DockSize = .medium
    @AppStorage("centerTaskbarIcons") private var centerTaskbarIcons = true
    @AppStorage("showSystemTray") private var showSystemTray = true
    @AppStorage("showTaskView") private var showTaskView = true
    @AppStorage("showLabels") private var showLabels = false
    @AppStorage("useSmallTaskbarButtons") private var useSmallTaskbarButtons = false
    @AppStorage("taskbarTransparency") private var taskbarTransparency = 0.95

    var body: some View {
        GeometryReader { geometry in
            dockMainContent(geometry: geometry)
        }
        .background(Color.clear)
        .onAppear {
            appManager.startMonitoring()
            setupDropHandler()
        }
        .onDisappear {
            appManager.stopMonitoring()
            removeDropHandler()
        }
    }
    
    // Computed property for background material
    private var backgroundMaterial: some ShapeStyle {
        if taskbarTransparency >= 0.95 {
            // Use glass effect for high transparency
            return AnyShapeStyle(.regularMaterial)
        } else if taskbarTransparency >= 0.7 {
            // Use blurred material for medium transparency
            return AnyShapeStyle(.thinMaterial)
        } else {
            // Use solid color for low transparency
            return AnyShapeStyle(Color(NSColor.windowBackgroundColor))
        }
    }

    @ViewBuilder
    private func dockMainContent(geometry: GeometryProxy) -> some View {
        ZStack(alignment: .bottom) {
            // Modern taskbar background with optional transparency
            Rectangle()
                .fill(backgroundMaterial)
                .opacity(taskbarTransparency)
                .frame(width: geometry.size.width, height: 54)
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.1),
                                    Color.clear,
                                    Color.black.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    Rectangle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.clear,
                                    Color.black.opacity(0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: -2)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Single click - do nothing or handle focus
                }
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded { _ in
                        // Double-click to show desktop
                        showDesktop()
                    }
                )
                .contextMenu {
                    DockContextMenuView(appManager: appManager)
                }
            
            // Main taskbar content
            HStack(spacing: 0) {
                // Left side - Start button
                HStack(spacing: 4) {
                    StartButton()
                    
                    // Task View button (optional)
                    if showTaskView {
                        TaskViewButton()
                    }
                    
                    // Search button (optional)
                    SearchButton()
                }
                .padding(.leading, 8)
                
                // Center - App icons
                if centerTaskbarIcons && (dockPosition == .bottom || dockPosition == .top) {
                    Spacer()
                    dockIconsSection
                    Spacer()
                } else if dockPosition == .bottom || dockPosition == .top {
                    // Left-aligned icons for horizontal dock
                    dockIconsSection
                    Spacer()
                } else {
                    // For vertical docks (left/right), always center
                    Spacer(minLength: 12)
                    dockIconsSection
                    Spacer()
                }
                
                // Right side - System tray
                SystemTrayView()
                    .padding(.trailing, 8)
            }
            .frame(width: geometry.size.width, height: 54)
        }
    }
    
    private func showDesktop() {
        let script = """
        tell application "System Events"
            key code 103 using {command down}
        end tell
        """
        executeAppleScript(script)
    }
    
    @discardableResult
    private func executeAppleScript(_ script: String) -> Bool {
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var error: NSDictionary?
        _ = appleScript.executeAndReturnError(&error)
        if let error = error {
            AppLogger.shared.error("AppleScript error: \(error)")
            return false
        }
        return true
    }

    private func setupDropHandler() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DockIconDropped"),
            object: nil,
            queue: .main
        ) { notification in
            handleIconDrop(notification)
        }
    }
    
    private func removeDropHandler() {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("DockIconDropped"), object: nil)
    }
    
    private func handleIconDrop(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let droppedApp = userInfo["app"] as? DockApp,
              let locationValue = userInfo["location"] as? NSValue else { return }
        
        let location = locationValue.pointValue
        
        // Calculate drop position
        if let fromIndex = appManager.dockApps.firstIndex(of: droppedApp) {
            let toIndex = calculateDropIndex(at: location)
            if fromIndex != toIndex {
                // Add visual feedback
                withAnimation(.easeInOut(duration: 0.2)) {
                    dropInsertionIndex = toIndex
                }
                
                // Perform the move after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    appManager.moveApp(from: fromIndex, to: toIndex)
                    
                    // Clear the visual feedback
                    withAnimation(.easeInOut(duration: 0.2)) {
                        dropInsertionIndex = nil
                    }
                }
            }
        }
    }
    
    private func calculateDropIndex(at location: CGPoint) -> Int {
        let iconWidth: CGFloat = 56 // Icon width + spacing
        let startX: CGFloat = centerTaskbarIcons ? (NSScreen.main?.frame.width ?? 1920) / 2 - CGFloat(appManager.dockApps.count * 28) : 120
        
        if dockPosition == .bottom || dockPosition == .top {
            let relativeX = location.x - startX
            let index = max(0, Int((relativeX + iconWidth/2) / iconWidth))
            return min(index, appManager.dockApps.count)
        } else {
            // For vertical docks
            let iconHeight: CGFloat = 56
            let startY: CGFloat = 100 // Approximate start position
            let relativeY = location.y - startY
            let index = max(0, Int((relativeY + iconHeight/2) / iconHeight))
            return min(index, appManager.dockApps.count)
        }
    }

    @ViewBuilder
    private var dockIconsSection: some View {
        if dockPosition == .bottom || dockPosition == .top {
            HStack(spacing: 2) {
                ForEach(Array(appManager.dockApps.enumerated()), id: \.element.id) { index, app in
                    WindowsTaskbarIcon(
                        app: app,
                        iconSize: dockSize.iconSize,
                        appManager: appManager
                    )
                    .background(
                        // Drop indicator
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.3))
                            .frame(width: 2)
                            .opacity(dropInsertionIndex == index ? 1.0 : 0.0)
                            .offset(x: -28)
                    )
                }
                
                // Final drop indicator
                Rectangle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: 2, height: 40)
                    .opacity(dropInsertionIndex == appManager.dockApps.count ? 1.0 : 0.0)
            }
        } else {
            VStack(spacing: 2) {
                ForEach(Array(appManager.dockApps.enumerated()), id: \.element.id) { index, app in
                    WindowsTaskbarIcon(
                        app: app,
                        iconSize: dockSize.iconSize,
                        appManager: appManager
                    )
                    .background(
                        // Drop indicator for vertical dock
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.3))
                            .frame(height: 2)
                            .opacity(dropInsertionIndex == index ? 1.0 : 0.0)
                            .offset(y: -28)
                    )
                }
                
                // Final drop indicator for vertical dock
                Rectangle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: 40, height: 2)
                    .opacity(dropInsertionIndex == appManager.dockApps.count ? 1.0 : 0.0)
            }
        }
    }
}