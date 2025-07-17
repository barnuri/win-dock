import SwiftUI
import AppKit

struct DockView: View {
    @StateObject private var appManager = AppManager()
    @State private var hoveredApp: DockApp?
    @State private var showingPreview = false
    @State private var previewWindow: NSWindow?
    @State private var draggedApp: DockApp?
    @State private var showStartMenu = false
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
        }
        .onDisappear {
            appManager.stopMonitoring()
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

    @ViewBuilder
    private var dockIconsSection: some View {
        if dockPosition == .bottom || dockPosition == .top {
            HStack(spacing: 2) {
                ForEach(appManager.dockApps) { app in
                    WindowsTaskbarIcon(
                        app: app,
                        isHovered: hoveredApp?.id == app.id,
                        iconSize: dockSize.iconSize,
                        appManager: appManager
                    )
                    .onHover { hovering in
                        if hovering {
                            hoveredApp = app
                        } else if hoveredApp?.id == app.id {
                            hoveredApp = nil
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 2) {
                ForEach(appManager.dockApps) { app in
                    WindowsTaskbarIcon(
                        app: app,
                        isHovered: hoveredApp?.id == app.id,
                        iconSize: dockSize.iconSize,
                        appManager: appManager
                    )
                    .onHover { hovering in
                        if hovering {
                            hoveredApp = app
                        } else if hoveredApp?.id == app.id {
                            hoveredApp = nil
                        }
                    }
                }
            }
        }
    }
}