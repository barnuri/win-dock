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
    @AppStorage("taskbarTransparency") private var taskbarTransparency = 0.8
    @AppStorage("showLabels") private var showLabels = false
    @AppStorage("useSmallTaskbarButtons") private var useSmallTaskbarButtons = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                VisualEffectView(
                    material: .hudWindow,
                    blendingMode: .behindWindow
                )
                .opacity(taskbarTransparency)
                .frame(width: geometry.size.width, height: geometry.size.height)

                // Centered dock content with max width
                if dockPosition == .bottom || dockPosition == .top {
                    HStack {
                        Spacer(minLength: 0)
                        HStack(spacing: 4) {
                            StartButton(showMenu: $showStartMenu)
                                .popover(isPresented: $showStartMenu, arrowEdge: .bottom) {
                                    StartMenuView()
                                }
                            SearchButton()
                            if showTaskView {
                                TaskViewButton()
                            }
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 1, height: 24)
                                .padding(.horizontal, 4)
                            if centerTaskbarIcons {
                                Spacer(minLength: 0)
                            }
                            appIconsSection
                            Spacer(minLength: 0)
                            if showSystemTray {
                                SystemTrayView()
                                    .frame(height: 48)
                                    .padding(.trailing, 10)
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(maxWidth: 600, minHeight: geometry.size.height, maxHeight: geometry.size.height)
                        Spacer(minLength: 0)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    VStack {
                        Spacer(minLength: 0)
                        VStack(spacing: 4) {
                            StartButton(showMenu: $showStartMenu)
                                .popover(isPresented: $showStartMenu, arrowEdge: .bottom) {
                                    StartMenuView()
                                }
                            SearchButton()
                            if showTaskView {
                                TaskViewButton()
                            }
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 24, height: 1)
                                .padding(.vertical, 4)
                            appIconsSection
                            Spacer(minLength: 0)
                            if showSystemTray {
                                SystemTrayView()
                                    .frame(width: 48)
                                    .padding(.bottom, 10)
                            }
                        }
                        .padding(.vertical, 8)
                        .frame(minWidth: geometry.size.width, maxWidth: geometry.size.width, maxHeight: 600)
                        Spacer(minLength: 0)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .background(Color.clear)
        .onAppear {
            appManager.startMonitoring()
        }
        .onDisappear {
            appManager.stopMonitoring()
            hidePreview()
        }
    }
    
    private var appIconsSection: some View {
        Group {
            if dockPosition == .bottom || dockPosition == .top {
                HStack(spacing: 4) {
                    ForEach(appManager.dockApps) { app in
                        WindowsTaskbarIcon(
                            app: app,
                            isHovered: hoveredApp?.id == app.id,
                            iconSize: dockSize.iconSize,
                            onTap: {
                                if let currentApp = appManager.dockApps.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                                    if currentApp.isRunning && currentApp.runningApplication?.isActive == true {
                                        appManager.hideApp(currentApp)
                                    } else {
                                        appManager.activateApp(currentApp)
                                    }
                                }
                            },
                            onRightClick: { location in
                                showContextMenu(for: app, at: location)
                            },
                            appManager: appManager
                        )
                        .onHover { hovering in
                            if hovering {
                                hoveredApp = app
                                // showPreview(for: app)
                            } else {
                                hoveredApp = nil
                                hidePreview()
                            }
                        }
                        .onDrag {
                            self.draggedApp = app
                            return NSItemProvider(object: app.bundleIdentifier as NSString)
                        }
                        .onDrop(of: [.text], delegate: AppDropDelegate(
                            app: app,
                            appManager: appManager,
                            draggedApp: $draggedApp
                        ))
                    }
                }
            } else {
                VStack(spacing: 4) {
                    ForEach(appManager.dockApps) { app in
                        WindowsTaskbarIcon(
                            app: app,
                            isHovered: hoveredApp?.id == app.id,
                            iconSize: dockSize.iconSize,
                            onTap: {
                                if let currentApp = appManager.dockApps.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                                    if currentApp.isRunning && currentApp.runningApplication?.isActive == true {
                                        appManager.hideApp(currentApp)
                                    } else {
                                        appManager.activateApp(currentApp)
                                    }
                                }
                            },
                            onRightClick: { location in
                                showContextMenu(for: app, at: location)
                            },
                            appManager: appManager
                        )
                        .onHover { hovering in
                            if hovering {
                                hoveredApp = app
                                // showPreview(for: app)
                            } else {
                                hoveredApp = nil
                                hidePreview()
                            }
                        }
                        .onDrag {
                            self.draggedApp = app
                            return NSItemProvider(object: app.bundleIdentifier as NSString)
                        }
                        .onDrop(of: [.text], delegate: AppDropDelegate(
                            app: app,
                            appManager: appManager,
                            draggedApp: $draggedApp
                        ))
                    }
                }
            }
        }
    }

    private func showContextMenu(for app: DockApp, at location: CGPoint) {
    AppMenuHandler.shared.appManager = appManager
    let menu = NSMenu()
    // Add app name at the top, disabled
    let appName = app.name.isEmpty ? app.bundleIdentifier : app.name
    let appNameItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
    appNameItem.isEnabled = false
    menu.addItem(appNameItem)
    menu.addItem(NSMenuItem.separator())
        if app.isRunning {
            let previewItem = NSMenuItem(title: "Show Windows Preview", action: #selector(AppMenuHandler.showWindowsPreview(_:)), keyEquivalent: "")
            previewItem.representedObject = app
            previewItem.target = AppMenuHandler.shared
            menu.addItem(previewItem)
            let showAllItem = NSMenuItem(title: "Show All Windows", action: #selector(AppMenuHandler.showAllWindows(_:)), keyEquivalent: "")
            showAllItem.representedObject = app
            showAllItem.target = AppMenuHandler.shared
            menu.addItem(showAllItem)
            if app.windows.count > 0 {
                menu.addItem(NSMenuItem.separator())
                for (index, window) in app.windows.enumerated() {
                    let windowTitle = window.title.isEmpty ? "Window \(index + 1)" : window.title
                    let windowItem = NSMenuItem(title: windowTitle, action: #selector(AppMenuHandler.focusWindow(_:)), keyEquivalent: "")
                    windowItem.representedObject = WindowMenuInfo(app: app, windowID: window.windowID)
                    windowItem.target = AppMenuHandler.shared
                    menu.addItem(windowItem)
                }
                menu.addItem(NSMenuItem.separator())
                let closeAllItem = NSMenuItem(title: "Close All Windows", action: #selector(AppMenuHandler.closeAllWindows(_:)), keyEquivalent: "")
                closeAllItem.representedObject = app
                closeAllItem.target = AppMenuHandler.shared
                menu.addItem(closeAllItem)
            }
            menu.addItem(NSMenuItem.separator())
            let hideItem = NSMenuItem(title: "Hide", action: #selector(AppMenuHandler.hideApp(_:)), keyEquivalent: "")
            hideItem.representedObject = app
            hideItem.target = AppMenuHandler.shared
            menu.addItem(hideItem)
            menu.addItem(NSMenuItem.separator())
            let quitItem = NSMenuItem(title: "Quit", action: #selector(AppMenuHandler.quitApp(_:)), keyEquivalent: "")
            quitItem.representedObject = app
            quitItem.target = AppMenuHandler.shared
            menu.addItem(quitItem)
        } else {
            let openItem = NSMenuItem(title: "Open", action: #selector(AppMenuHandler.openApp(_:)), keyEquivalent: "")
            openItem.representedObject = app
            openItem.target = AppMenuHandler.shared
            menu.addItem(openItem)
        }
        menu.addItem(NSMenuItem.separator())
        if app.isPinned {
            let unpinItem = NSMenuItem(title: "Unpin from taskbar", action: #selector(AppMenuHandler.unpinApp(_:)), keyEquivalent: "")
            unpinItem.representedObject = app
            unpinItem.target = AppMenuHandler.shared
            unpinItem.action = #selector(AppMenuHandler.unpinApp(_:))
            menu.addItem(unpinItem)
        } else {
            let pinItem = NSMenuItem(title: "Pin to taskbar", action: #selector(AppMenuHandler.pinApp(_:)), keyEquivalent: "")
            pinItem.representedObject = app
            pinItem.target = AppMenuHandler.shared
            pinItem.action = #selector(AppMenuHandler.pinApp(_:))
            menu.addItem(pinItem)
        }
        if app.isRunning {
            menu.addItem(NSMenuItem.separator())
            let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
            recentItem.isEnabled = false
            menu.addItem(recentItem)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: location.x, y: location.y), in: nil)
    }

    private func showPreview(for app: DockApp) {
        hidePreview()
        DispatchQueue.main.async {
            let previewView = WindowsAppPreviewView(app: app)
            let hostingView = NSHostingView(rootView: previewView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 250, height: 180),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.contentView = hostingView
            if let screen = NSScreen.main {
                let mouseLocation = NSEvent.mouseLocation
                let screenFrame = screen.frame
                let previewY: CGFloat
                let previewX = mouseLocation.x - 125
                switch dockPosition {
                case .bottom:
                    previewY = 60
                case .top:
                    previewY = screenFrame.height - 240
                case .left, .right:
                    previewY = mouseLocation.y - 90
                }
                window.setFrameOrigin(NSPoint(x: previewX, y: previewY))
            }
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

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct DockButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct DockAppIcon: View {
    let app: DockApp
    let size: CGFloat
    let showLabel: Bool
    let isHovered: Bool
    let appManager: AppManager
    
    @State private var showContextMenu = false
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                // App icon
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                }
                
                // Running indicator
                if app.isRunning {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .offset(x: 2, y: 2)
                }
                
                // Window count badge
                if app.windowCount > 1 {
                    Text("\(app.windowCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(2)
                        .background(
                            Circle()
                                .fill(Color.red)
                        )
                        .offset(x: 4, y: -4)
                }
            }
            .scaleEffect(isHovered ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            
            if showLabel {
                Text(app.name)
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: size * 1.5)
            }
        }
        .onTapGesture {
            appManager.activateApp(app)
        }
        .contextMenu {
            appContextMenu
        }
    }
    
    @ViewBuilder
    private var appContextMenu: some View {
        if app.isRunning {
            Button("Show All Windows") {
                appManager.showAllWindows(for: app)
            }
            
            Divider()
            
            Button("Hide") {
                appManager.hideApp(app)
            }
            
            Button("Quit") {
                appManager.quitApp(app)
            }
            
            Divider()
        }
        
        if app.isPinned {
            Button("Unpin from taskbar") {
                appManager.unpinApp(app)
            }
        } else {
            Button("Pin to taskbar") {
                appManager.pinApp(app)
            }
        }
        
        if !app.isRunning {
            Divider()
            
            Button("Open") {
                appManager.launchApp(app)
            }
            
            Button("Open new window") {
                appManager.launchNewInstance(app)
            }
        }
    }
}

enum SearchAppChoice: String, CaseIterable {
    case spotlight = "spotlight"
    case raycast = "raycast"
    case alfred = "alfred"
    
    var displayName: String {
        switch self {
        case .spotlight: return "Spotlight"
        case .raycast: return "Raycast"
        case .alfred: return "Alfred"
        }
    }
}


// Windows style app preview
struct WindowsAppPreviewView: View {
    let app: DockApp
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Text(app.name)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.1))
            
            // Preview area
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Text("Window Preview")
                        .font(.caption)
                        .foregroundColor(.gray)
                )
        }
        .frame(width: 250, height: 180)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}


// Menu handler for NSMenu actions
@MainActor
class AppMenuHandler: NSObject {
    static let shared = AppMenuHandler()
    var appManager: AppManager?
    
    @objc func showWindowsPreview(_ sender: NSMenuItem) {
        if let app = sender.representedObject as? DockApp {
            Task { @MainActor in
                showWindowsPreviewPanel(for: app)
            }
        }
    }
    
    @objc func showAllWindows(_ sender: NSMenuItem) {
        if let app = sender.representedObject as? DockApp {
            Task { @MainActor in
                appManager?.showAllWindows(for: app)
            }
        }
    }
    
    @objc func focusWindow(_ sender: NSMenuItem) {
        if let info = sender.representedObject as? WindowMenuInfo {
            Task { @MainActor in
                focusSpecificWindow(windowID: info.windowID, app: info.app)
            }
        }
    }
    
    @objc func closeAllWindows(_ sender: NSMenuItem) {
        if let app = sender.representedObject as? DockApp {
            Task { @MainActor in
                closeAllWindowsForApp(app)
            }
        }
    }
    
    @objc func hideApp(_ sender: NSMenuItem) {
        if let app = sender.representedObject as? DockApp {
            Task { @MainActor in
                appManager?.hideApp(app)
            }
        }
    }
    
    @objc func quitApp(_ sender: NSMenuItem) {
        if let app = sender.representedObject as? DockApp {
            Task { @MainActor in
                appManager?.quitApp(app)
            }
        }
    }
    
    @objc func openApp(_ sender: NSMenuItem) {
        if let app = sender.representedObject as? DockApp {
            Task { @MainActor in
                appManager?.launchApp(app)
            }
        }
    }
    
    @objc func pinApp(_ sender: NSMenuItem) {
        if let app = sender.representedObject as? DockApp {
            Task { @MainActor in
                appManager?.pinApp(app)
            }
        }
    }
    
    @objc func unpinApp(_ sender: NSMenuItem) {
        if let app = sender.representedObject as? DockApp {
            Task { @MainActor in
                appManager?.unpinApp(app)
            }
        }
    }
    
    func showWindowsPreviewPanel(for app: DockApp) {
        let previewWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        previewWindow.title = "\(app.name) - Windows Preview"
        previewWindow.center()
        
        let previewView = WindowsPreviewGridView(app: app, appManager: appManager ?? AppManager())
        let hostingView = NSHostingView(rootView: previewView)
        previewWindow.contentView = hostingView
        
        previewWindow.makeKeyAndOrderFront(nil)
    }
    
    func focusSpecificWindow(windowID: CGWindowID, app: DockApp) {
        if let runningApp = app.runningApplication {
            if #available(macOS 14.0, *) {
                runningApp.activate()
            } else {
                runningApp.activate(options: [.activateIgnoringOtherApps])
            }
            
            // Use accessibility API to focus the specific window
            let axApp = AXUIElementCreateApplication(runningApp.processIdentifier)
            var windows: CFTypeRef?
            AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windows)
            
            if let windowArray = windows as? [AXUIElement] {
                for window in windowArray {
                    var windowIDRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, "_AXWindowNumber" as CFString, &windowIDRef)
                    
                    if let windowNumber = windowIDRef as? Int, windowNumber == windowID {
                        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                        break
                    }
                }
            }
        }
    }
    
    func closeAllWindowsForApp(_ app: DockApp) {
        guard app.runningApplication != nil else { return }
        
        let script = """
        tell application "System Events"
            tell process "\(app.name)"
                set windowList to every window
                repeat with aWindow in windowList
                    click button 1 of aWindow
                end repeat
            end tell
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}

// Helper struct for window menu items
struct WindowMenuInfo {
    let app: DockApp
    let windowID: CGWindowID
}


// Windows preview grid view
struct WindowsPreviewGridView: View {
    let app: DockApp
    let appManager: AppManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            Text("\(app.name) - \(app.windows.count) Window\(app.windows.count == 1 ? "" : "s")")
                .font(.headline)
                .padding()
            
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250))], spacing: 20) {
                    ForEach(Array(app.windows.enumerated()), id: \.element.windowID) { index, window in
                        WindowPreviewTile(
                            window: window,
                            app: app,
                            index: index,
                            onTap: {
                                AppMenuHandler.shared.focusSpecificWindow(windowID: window.windowID, app: app)
                                dismiss()
                            },
                            onClose: {
                                closeWindow(window: window, app: app)
                            }
                        )
                    }
                }
                .padding()
            }
            
            HStack {
                Button("Close All") {
                    AppMenuHandler.shared.closeAllWindowsForApp(app)
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    private func closeWindow(window: WindowInfo, app: DockApp) {
        guard let runningApp = app.runningApplication else { return }
        
        let axApp = AXUIElementCreateApplication(runningApp.processIdentifier)
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windows)
        
        if let windowArray = windows as? [AXUIElement] {
            for axWindow in windowArray {
                var windowIDRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, "_AXWindowNumber" as CFString, &windowIDRef)
                
                if let windowNumber = windowIDRef as? Int, windowNumber == window.windowID {
                    var closeButton: CFTypeRef?
                    AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeButton)
                    if let button = closeButton {
                        AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
                    }
                    break
                }
            }
        }
    }
}

// Window preview tile
struct WindowPreviewTile: View {
    let window: WindowInfo
    let app: DockApp
    let index: Int
    let onTap: () -> Void
    let onClose: () -> Void
    @State private var isHovered = false
    @State private var thumbnailImage: NSImage?
    
    var body: some View {
        VStack(spacing: 0) {
            // Window content preview
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 150)
                
                if let image = thumbnailImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 150)
                } else {
                    VStack {
                        Image(systemName: "rectangle.dashed")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("Window \(index + 1)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                // Close button overlay
                if isHovered {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: onClose) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .background(Circle().fill(Color.red))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(8)
                        }
                        Spacer()
                    }
                }
            }
            
            // Window title
            Text(window.title.isEmpty ? "Window \(index + 1)" : window.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
        }
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap()
        }
        .onAppear {
            captureWindowThumbnail()
        }
    }
    
    private func captureWindowThumbnail() {
        // Use ScreenCaptureKit for window thumbnails
        Task {
            if #available(macOS 13.0, *) {
                // await captureWithScreenCaptureKit()
            }
        }
    }
    
}


// Drop delegate for drag and drop
struct AppDropDelegate: DropDelegate {
    let app: DockApp
    let appManager: AppManager
    @Binding var draggedApp: DockApp?
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedApp = self.draggedApp else { return false }
        
        var apps = appManager.dockApps
        let fromIndex = apps.firstIndex(of: draggedApp)
        let toIndex = apps.firstIndex(of: app)
        
        if let from = fromIndex, let to = toIndex, from != to {
            withAnimation {
                apps.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                appManager.dockApps = apps
            }
            Task { @MainActor in
                appManager.saveDockAppOrder()
            }
        }
        
        self.draggedApp = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        // Optional: Add visual feedback
    }
    
    func dropExited(info: DropInfo) {
        // Optional: Remove visual feedback
    }
}