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
    @AppStorage("taskbarTransparency") private var taskbarTransparency = 1.0 // Set to solid

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
            Rectangle()
                .fill(Color(.windowBackgroundColor).opacity(0.95))
                .frame(width: geometry.size.width, height: 54)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 2)
                .overlay(
                    Rectangle()
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    // Double-click fallback (optional)
                }
                .onTapGesture {
                    if NSEvent.modifierFlags.contains(.control) {
                        showDockMenu(at: NSEvent.mouseLocation)
                    }
                }
            HStack(spacing: 4) {
                dockIconsSection
            }
            .frame(width: geometry.size.width, height: 54)
        }
    }
    private func showDockMenu(at location: CGPoint) {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(AppDelegate.openSettingsMenu), keyEquivalent: "")
        settingsItem.target = NSApp.delegate
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit Win Dock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        menu.popUp(positioning: nil, at: location, in: nil)
    }

    @ViewBuilder
    private var dockIconsSection: some View {
        if dockPosition == .bottom || dockPosition == .top {
            HStack(spacing: 4) {
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
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 4) {
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
                        }
                    }
                }
            }
        }
    }
}