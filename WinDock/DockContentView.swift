import SwiftUI
import AppKit
import Foundation

// Helper view for each app icon in the dock
// Add preview at file scope
#if DEBUG
#Preview {
    DockContentView(dockSize: .medium)
        .frame(height: 80)
}
#endif

struct DockContentView: View {
    @StateObject private var appManager = AppManager()
    @State private var hoveredApp: DockApp?
    @State private var showingPreview = false
    @State private var previewWindow: NSWindow?
    @AppStorage("dockPosition") private var dockPosition: DockPosition = .bottom
    let dockSize: DockSize

    init(dockSize: DockSize = .medium) {
        self.dockSize = dockSize
    }

    var body: some View {
        let isVertical = dockPosition == .left || dockPosition == .right
        GeometryReader { geometry in
            VStack {
                Spacer()
                HStack {
                    Spacer(minLength: 0)
                    Group {
                        if isVertical {
                            VStack(spacing: 8) {
                                LauncherMenuIcon()
                                ForEach(appManager.dockApps) { app in
                                    DockAppView(
                                        app: app,
                                        isHovered: hoveredApp?.id == app.id,
                                        iconSize: dockSize.iconSize,
                                        onTap: {
                                            appManager.activateApp(app)
                                        }
                                    )
                                    .onHover { hovering in
                                        if hovering {
                                            hoveredApp = app
                                            showPreview(for: app)
                                        } else {
                                            hoveredApp = nil
                                            hidePreview()
                                        }
                                    }
                                    .contextMenu {
                                        AppContextMenu(app: app, appManager: appManager)
                                    }
                                }
                            }
                        } else {
                            HStack(spacing: 8) {
                                LauncherMenuIcon()
                                ForEach(appManager.dockApps) { app in
                                    DockAppView(
                                        app: app,
                                        isHovered: hoveredApp?.id == app.id,
                                        iconSize: dockSize.iconSize,
                                        onTap: {
                                            appManager.activateApp(app)
                                        }
                                    )
                                    .onHover { hovering in
                                        if hovering {
                                            hoveredApp = app
                                            showPreview(for: app)
                                        } else {
                                            hoveredApp = nil
                                            hidePreview()
                                        }
                                    }
                                    .contextMenu {
                                        AppContextMenu(app: app, appManager: appManager)
                                    }
                                }
                            }
                        }
                    }
                    .padding(isVertical ? .vertical : .horizontal, 8)
                    .padding(isVertical ? .horizontal : .vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.85))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 6)
                    )
                    .frame(maxWidth: geometry.size.width * 0.98)
                    .frame(height: 64)
                    .padding(.bottom, 8)
                    Spacer(minLength: 0)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
        .background(Color.clear)
        .contextMenu {
            DockContextMenu()
        }
        .onAppear {
            appManager.startMonitoring()
        }
        .onDisappear {
            appManager.stopMonitoring()
            hidePreview()
        }
    }

    private func showPreview(for app: DockApp) {
        hidePreview()
        DispatchQueue.main.async {
            let previewView = AppPreviewView(app: app)
            let hostingView = NSHostingView(rootView: previewView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 150),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.contentView = hostingView
            let mouseLocation = NSEvent.mouseLocation
            let screen = NSScreen.main
            let yCoord = screen != nil ? (screen!.frame.height - mouseLocation.y) : mouseLocation.y
            let previewFrame = NSRect(
                x: mouseLocation.x - 100,
                y: yCoord + 50,
                width: 200,
                height: 150
            )
            window.setFrame(previewFrame, display: true)
            window.orderFront(nil)
            self.previewWindow = window
            AppLogger.shared.info("Preview window shown for app: \(app.name)")
        }
    }

    private func hidePreview() {
        DispatchQueue.main.async {
            if let window = self.previewWindow {
                window.orderOut(nil)
                window.close()
                self.previewWindow = nil
                AppLogger.shared.info("Preview window hidden")
            }
        }
    }
}




fileprivate func minimizeAllWindows() {
    // Only works for Finder windows
    let script = "tell application \"Finder\" to set collapsed of every window to true"
    if let appleScript = NSAppleScript(source: script) {
        var errorDict: NSDictionary? = nil
        appleScript.executeAndReturnError(&errorDict)
        if let errorDict = errorDict {
            AppLogger.shared.warn("AppleScript error in minimizeAllWindows: \(errorDict)")
        } else {
            AppLogger.shared.info("All Finder windows minimized via AppleScript")
        }
    }
}

fileprivate func closeAllWindows() {
    let script = "tell application \"System Events\" to keystroke 'w' using {command down, option down}"
    if let appleScript = NSAppleScript(source: script) {
        var errorDict: NSDictionary? = nil
        appleScript.executeAndReturnError(&errorDict)
        if let errorDict = errorDict {
            AppLogger.shared.warn("AppleScript error in closeAllWindows: \(errorDict)")
        } else {
            AppLogger.shared.info("All windows closed via AppleScript")
        }
    }
}

fileprivate func openSettings() {
    if let appDelegate = NSApp.delegate as? AppDelegate {
        appDelegate.openSettings()
        AppLogger.shared.info("Settings opened from dock context menu")
    }
}

fileprivate func lockScreen() {
    do {
        let task = Process()
        task.launchPath = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        task.arguments = ["-suspend"]
        try task.run()
        AppLogger.shared.info("Lock screen triggered from dock menu")
    } catch {
        AppLogger.shared.error("Error in lockScreen: \(error)")
    }
}

fileprivate func openMonitor() {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: { _, error in
            if let error = error {
                AppLogger.shared.warn("Error opening Activity Monitor: \(error)")
            } else {
                AppLogger.shared.info("Activity Monitor opened from dock menu")
            }
        })
    }
}


struct LauncherMenuIcon: View {
    @State private var showMenu = false
    var body: some View {
        Button(action: { showMenu.toggle() }) {
            Image(systemName: "circle.grid.3x3.fill")
                .resizable()
                .frame(width: 28, height: 28)
                .foregroundColor(.white)
                .padding(6)
                .background(Color.gray.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(PlainButtonStyle())
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Button("Lock Screen") { lockScreen() }
                Button("Open Monitor") { openMonitor() }
                Button("Minimize All Windows") { minimizeAllWindows() }
                Button("Close All Windows") { closeAllWindows() }
                Button("Settings...") { openSettings() }
            }
    }
}
}

struct DockAppView: View {
    let app: DockApp
    let isHovered: Bool
    let iconSize: CGFloat
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Background with Windows 11 style
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(strokeColor, lineWidth: 1)
                    )
                    .frame(width: iconSize + 12, height: iconSize + 12)
                    .scaleEffect(isHovered ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
                
                // App icon
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .scaleEffect(isHovered ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isHovered)
                }
                
                // Running indicator - Windows 11 style bottom line
                if app.isRunning {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: iconSize * 0.6, height: 2)
                        .cornerRadius(1)
                        .offset(y: (iconSize + 12) / 2 + 2)
                }
                
                // Badge for window count
                if app.windowCount > 1 {
                    Text("\(app.windowCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(Color.red)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 1)
                                )
                        )
                        .offset(x: (iconSize + 12) / 2 - 4, y: -(iconSize + 12) / 2 + 4)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: iconSize + 16, height: iconSize + 16)
    }
    
    private var backgroundFill: some ShapeStyle {
        if isHovered {
            return AnyShapeStyle(.regularMaterial)
        } else if app.isRunning {
            return AnyShapeStyle(.thinMaterial)
        } else {
            return AnyShapeStyle(.clear)
        }
    }
    
    private var strokeColor: Color {
        if isHovered {
            return .white.opacity(0.3)
        } else if app.isRunning {
            return .white.opacity(0.15)
        } else {
            return .clear
        }
    }
}

struct AppContextMenu: View {
    let app: DockApp
    let appManager: AppManager
    
    var body: some View {
        Group {
            if app.isRunning {
                Button("Show All Windows") {
                    appManager.showAllWindows(for: app)
                }
                
                Button("Hide") {
                    appManager.hideApp(app)
                }
                
                Divider()
                
                Button("Quit") {
                    appManager.quitApp(app)
                }
            } else {
                Button("Open") {
                    appManager.launchApp(app)
                }
            }
            
            Divider()
            
            if app.isPinned {
                Button("Unpin from Dock") {
                    appManager.unpinApp(app)
                }
            } else {
                Button("Pin to Dock") {
                    appManager.pinApp(app)
                }
            }
        }
    }
}

struct DockContextMenu: View {
    @AppStorage("dockPosition") private var dockPosition: DockPosition = .bottom
    
    var body: some View {
        Group {
            Button("Settings...") {
                openSettings()
            }
            
            Divider()
            
            Menu("Change Position") {
                Button("Bottom") {
                    dockPosition = .bottom
                }
                .disabled(dockPosition == .bottom)
                
                Button("Top") {
                    dockPosition = .top
                }
                .disabled(dockPosition == .top)
                
                Button("Left") {
                    dockPosition = .left
                }
                .disabled(dockPosition == .left)
                
                Button("Right") {
                    dockPosition = .right
                }
                .disabled(dockPosition == .right)
            }
            
            Divider()
            
            Button("Quit Win Dock") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    private func openSettings() {
        // Get the app delegate
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.openSettings()
        }
    }
}

struct AppPreviewView: View {
    let app: DockApp
    
    var body: some View {
        VStack(spacing: 8) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Text(app.name)
                .font(.headline)
                .foregroundColor(.primary)
            
            if app.isRunning && app.windowCount > 0 {
                Text("\(app.windowCount) window\(app.windowCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
        )
        .offset(y: -120)
    }
}

