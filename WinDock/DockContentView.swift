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
    @State private var draggedApp: DockApp?
    @State private var showStartMenu = false
    @AppStorage("dockPosition") private var dockPosition: DockPosition = .bottom
    @AppStorage("showSystemTray") private var showSystemTray: Bool = true
    @AppStorage("showTaskView") private var showTaskView: Bool = true
    @AppStorage("centerTaskbarIcons") private var centerTaskbarIcons: Bool = true
    
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
                    if centerTaskbarIcons && !isVertical {
                        Spacer()
                    }
                    
                    Group {
                        if isVertical {
                            VStack(spacing: 4) {
                                taskbarContent
                            }
                        } else {
                            HStack(spacing: 4) {
                                taskbarContent
                            }
                        }
                    }
                    .padding(6)
                    .background(
                        WindowsTaskbarBackground()
                    )
                    .frame(maxWidth: isVertical ? nil : (centerTaskbarIcons ? nil : geometry.size.width * 0.98))
                    .frame(height: isVertical ? nil : 48)
                    .padding(.bottom, 2)
                    
                    if centerTaskbarIcons && !isVertical {
                        Spacer()
                    }
                    
                    // System tray area for horizontal dock
                    if !isVertical && showSystemTray {
                        SystemTrayView()
                            .frame(height: 48)
                            .padding(.trailing, 10)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
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
    
    @ViewBuilder
    private var taskbarContent: some View {
        // Start button
        StartButton(showMenu: $showStartMenu)
            .popover(isPresented: $showStartMenu, arrowEdge: .bottom) {
                StartMenuView()
            }
        
        // Search button
        SearchButton()
        
        // Task view button
        if showTaskView {
            TaskViewButton()
        }
        
        // Separator
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 4)
        
        // App icons with drag and drop
        ForEach(appManager.dockApps) { app in
            WindowsTaskbarIcon(
                app: app,
                isHovered: hoveredApp?.id == app.id,
                iconSize: dockSize.iconSize,
                onTap: {
                    appManager.activateApp(app)
                },
                onRightClick: { location in
                    showContextMenu(for: app, at: location)
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
            .onDrag {
                self.draggedApp = app
                return NSItemProvider(object: app.bundleIdentifier as NSString)
            }
            .onDrop(of: [.text], delegate: AppDropDelegate(
                app: app,
                apps: $appManager.dockApps,
                draggedApp: $draggedApp,
                appManager: appManager
            ))
        }
    }
    
    private func showContextMenu(for app: DockApp, at location: CGPoint) {
        let menu = NSMenu()
        
        if app.isRunning {
            let showAllItem = NSMenuItem(title: "Show All Windows", action: #selector(AppMenuHandler.showAllWindows(_:)), keyEquivalent: "")
            showAllItem.representedObject = app
            showAllItem.target = AppMenuHandler.shared
            menu.addItem(showAllItem)
            
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
            menu.addItem(unpinItem)
        } else {
            let pinItem = NSMenuItem(title: "Pin to taskbar", action: #selector(AppMenuHandler.pinApp(_:)), keyEquivalent: "")
            pinItem.representedObject = app
            pinItem.target = AppMenuHandler.shared
            menu.addItem(pinItem)
        }
        
        // Add recent documents if available
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
            
            // Position above the icon
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

// Windows 11 style taskbar background
struct WindowsTaskbarBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Base layer with blur effect
            Rectangle()
                .fill(.ultraThinMaterial)
            
            // Acrylic-like overlay
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(white: colorScheme == .dark ? 0.15 : 0.95).opacity(0.8),
                            Color(white: colorScheme == .dark ? 0.1 : 0.9).opacity(0.6)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Top border highlight
            VStack {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
    }
}

// Windows 11 style start button
struct StartButton: View {
    @Binding var showMenu: Bool
    @State private var isHovered = false
    
    var body: some View {
        Button(action: { showMenu.toggle() }) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 18))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// Windows 11 style search button
struct SearchButton: View {
    @State private var isHovered = false
    
    var body: some View {
        Button(action: { 
            // Open Spotlight search
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.spotlight")!)
        }) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// Task view button
struct TaskViewButton: View {
    @State private var isHovered = false
    
    var body: some View {
        Button(action: { 
            // Trigger Mission Control
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.exposelauncher") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } else {
                // Fallback: Use key event
                let src = CGEventSource(stateID: .hidSystemState)
                let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x7E, keyDown: true) // F3 key
                let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x7E, keyDown: false)
                keyDown?.post(tap: .cghidEventTap)
                keyUp?.post(tap: .cghidEventTap)
            }
        }) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// Windows 11 style taskbar icon
struct WindowsTaskbarIcon: View {
    let app: DockApp
    let isHovered: Bool
    let iconSize: CGFloat
    let onTap: () -> Void
    let onRightClick: (CGPoint) -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(backgroundFill)
                        .frame(width: 40, height: 40)
                    
                    // App icon
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    }
                    
                    // Multiple window indicator
                    if app.windowCount > 1 {
                        HStack(spacing: 2) {
                            ForEach(0..<min(app.windowCount, 3), id: \.self) { _ in
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: 4, height: 2)
                                    .cornerRadius(1)
                            }
                        }
                        .offset(y: 23)
                    }
                }
                
                // Running indicator
                if app.isRunning {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: isHovered ? 30 : (app.windowCount > 0 ? 20 : 6), height: 3)
                        .cornerRadius(1.5)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                        .padding(.top, 2)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 30, height: 3)
                        .padding(.top, 2)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { _ in
                if app.isRunning {
                    // Open new window if supported
                    onTap()
                }
            }
        )
        .contextMenu {
            // This is a backup context menu for SwiftUI
            AppContextMenu(app: app, appManager: AppManager())
        }
        .onReceive(NotificationCenter.default.publisher(for: NSView.rightMouseDownNotification)) { _ in
            if let event = NSApp.currentEvent, event.type == .rightMouseDown {
                let location = event.locationInWindow
                onRightClick(location)
            }
        }
    }
    
    private var backgroundFill: some ShapeStyle {
        if isPressed {
            return AnyShapeStyle(Color.white.opacity(0.25))
        } else if isHovered {
            return AnyShapeStyle(Color.white.opacity(0.15))
        } else if app.isRunning {
            return AnyShapeStyle(Color.white.opacity(0.08))
        } else {
            return AnyShapeStyle(Color.clear)
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

// System tray view
struct SystemTrayView: View {
    @State private var currentTime = Date()
    @State private var showNotificationCenter = false
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 8) {
            // System icons
            Button(action: {}) {
                Image(systemName: "wifi")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {}) {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {}) {
                Image(systemName: "battery.75")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
            .buttonStyle(PlainButtonStyle())
            
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 1, height: 20)
            
            // Date and time
            VStack(alignment: .trailing, spacing: 2) {
                Text(currentTime, formatter: timeFormatter)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                Text(currentTime, formatter: dateFormatter)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
            }
            .onReceive(timer) { _ in
                currentTime = Date()
            }
            
            // Notification center button
            Button(action: { showNotificationCenter.toggle() }) {
                Image(systemName: "message")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy"
        return formatter
    }
}

// Start menu view
struct StartMenuView: View {
    @State private var searchText = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Type here to search", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
            }
            .padding(8)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(6)
            .padding()
            
            // Pinned apps
            VStack(alignment: .leading) {
                Text("Pinned")
                    .font(.headline)
                    .padding(.horizontal)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
                    ForEach(["Finder", "Safari", "Mail", "Messages"], id: \.self) { appName in
                        VStack {
                            Image(systemName: "app.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.blue)
                            Text(appName)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .frame(width: 80, height: 80)
                        .onTapGesture {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.\(appName.lowercased())") {
                                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                            }
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            Spacer()
            
            // Power options
            HStack {
                Button(action: {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    }
                    dismiss()
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20))
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button(action: {
                    lockScreen()
                    dismiss()
                }) {
                    Image(systemName: "lock")
                        .font(.system(size: 20))
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 20))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
        }
        .frame(width: 400, height: 500)
        .background(.regularMaterial)
    }
}

// App context menu
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
                Button("Unpin from taskbar") {
                    appManager.unpinApp(app)
                }
            } else {
                Button("Pin to taskbar") {
                    appManager.pinApp(app)
                }
            }
        }
    }
}

// Menu handler for NSMenu actions
@MainActor
class AppMenuHandler: NSObject {
    static let shared = AppMenuHandler()
    private let appManager = AppManager()
    
    @objc func showAllWindows(_ sender: NSMenuItem) {
        if let app = sender.representedObject as? DockApp {
            Task { @MainActor in
                appManager.showAllWindows(for: app)
            }
        }
    }
    
    @objc func hideApp(_ sender: NSMenuItem) {
        if let app = sender.representedObject as? DockApp {
            Task { @MainActor in
                appManager.hideApp(app)
            }
        }
    }
    
    @objc func quitApp(_ sender: NSMenuItem) {
        if let app = sender.representedObject as? DockApp {
            Task { @MainActor in
                appManager.quitApp(app)
            }
        }
    }
    
    @objc func openApp(_ sender: NSMenuItem) {
        if let app = sender.representedObject as? DockApp {
            Task { @MainActor in
                appManager.launchApp(app)
            }
        }
    }
    
    @objc func pinApp(_ sender: NSMenuItem) {
        if let app = sender.representedObject as? DockApp {
            Task { @MainActor in
                appManager.pinApp(app)
            }
        }
    }
    
    @objc func unpinApp(_ sender: NSMenuItem) {
        if let app = sender.representedObject as? DockApp {
            Task { @MainActor in
                appManager.unpinApp(app)
            }
        }
    }
}

// Drop delegate for drag and drop
struct AppDropDelegate: DropDelegate {
    let app: DockApp
    @Binding var apps: [DockApp]
    @Binding var draggedApp: DockApp?
    let appManager: AppManager
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedApp = self.draggedApp else { return false }
        
        let fromIndex = apps.firstIndex(of: draggedApp)
        let toIndex = apps.firstIndex(of: app)
        
        if let from = fromIndex, let to = toIndex, from != to {
            withAnimation {
                apps.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
            Task { @MainActor in
                appManager.saveDockAppOrder()
            }
        }
        
        return true
    }
}

// Fixed lock screen function
func lockScreen() {
    let script = """
    tell application "System Events"
        keystroke "q" using {command down, control down}
    end tell
    """
    
    if let appleScript = NSAppleScript(source: script) {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error = error {
            AppLogger.shared.error("Lock screen error: \(error)")
            // Fallback to screen saver
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-a", "ScreenSaverEngine"]
            task.launch()
        } else {
            AppLogger.shared.info("Lock screen triggered successfully")
        }
    }
}

// NSView extension for right-click detection
extension NSView {
    static let rightMouseDownNotification = Notification.Name("NSViewRightMouseDown")
    
    open override func rightMouseDown(with event: NSEvent) {
        NotificationCenter.default.post(name: NSView.rightMouseDownNotification, object: self)
        super.rightMouseDown(with: event)
    }
}