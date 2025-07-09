import SwiftUI
import AppKit

struct DockView: View {
    @ObservedObject var appManager: AppManager
    weak var dockWindow: DockWindow?
    @AppStorage("dockPosition") private var dockPosition: DockPosition = .bottom
    @AppStorage("dockSize") private var dockSize: DockSize = .medium
    @AppStorage("centerTaskbarIcons") private var centerTaskbarIcons = true
    @AppStorage("showSystemTray") private var showSystemTray = true
    @AppStorage("showTaskView") private var showTaskView = true
    @AppStorage("taskbarTransparency") private var taskbarTransparency = 0.8
    @AppStorage("showLabels") private var showLabels = false
    @AppStorage("useSmallTaskbarButtons") private var useSmallTaskbarButtons = false
    @State private var hoveredApp: DockApp?
    @State private var isDragging = false
    @State private var draggedApp: DockApp?
    
    let searchAppChoice: SearchAppChoice
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Full width background
                backgroundView
                    .frame(width: geometry.size.width, height: geometry.size.height)
                
                // Content
                if dockPosition == .bottom || dockPosition == .top {
                    horizontalLayout(in: geometry)
                } else {
                    verticalLayout(in: geometry)
                }
            }
        }
        .onDrop(of: ["public.data"], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private var backgroundView: some View {
        VisualEffectView(
            material: .hudWindow,
            blendingMode: .behindWindow
        )
        .opacity(taskbarTransparency)
        .overlay(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.1),
                    Color.white.opacity(0.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private func horizontalLayout(in geometry: GeometryProxy) -> some View {
        HStack(spacing: 4) {
            if showTaskView {
                taskViewButton
            }
            
            searchButton
            
            if centerTaskbarIcons {
                Spacer()
            }
            
            appIconsSection
            
            Spacer()
            
            if showSystemTray {
                systemTraySection
            }
        }
        .padding(.horizontal, 8)
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
    
    private func verticalLayout(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 4) {
            if showTaskView {
                taskViewButton
            }
            
            searchButton
            
            appIconsSection
            
            Spacer()
            
            if showSystemTray {
                systemTraySection
            }
        }
        .padding(.vertical, 8)
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
    
    private var taskViewButton: some View {
        Button(action: showMissionControl) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: iconSize * 0.4))
                .foregroundColor(.white)
                .frame(width: iconSize, height: iconSize)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                )
        }
        .buttonStyle(DockButtonStyle())
    }
    
    private var searchButton: some View {
        Button(action: openSearch) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: iconSize * 0.5))
                .foregroundColor(.white)
                .frame(width: iconSize, height: iconSize)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                )
        }
        .buttonStyle(DockButtonStyle())
    }
    
    private var appIconsSection: some View {
        Group {
            if dockPosition == .bottom || dockPosition == .top {
                HStack(spacing: 4) {
                    ForEach(appManager.dockApps) { app in
                        appIcon(for: app)
                    }
                }
            } else {
                VStack(spacing: 4) {
                    ForEach(appManager.dockApps) { app in
                        appIcon(for: app)
                    }
                }
            }
        }
    }
    
    private func appIcon(for app: DockApp) -> some View {
        DockAppIcon(
            app: app,
            size: iconSize,
            showLabel: showLabels,
            isHovered: hoveredApp?.id == app.id,
            appManager: appManager
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                hoveredApp = hovering ? app : nil
            }
        }
        .onDrag {
            self.draggedApp = app
            return NSItemProvider(object: app.bundleIdentifier as NSString)
        }
        .onDrop(of: ["public.data"], isTargeted: nil) { providers in
            handleAppReorder(providers: providers, targetApp: app)
        }
    }
    
    private var systemTraySection: some View {
        Group {
            if dockPosition == .bottom || dockPosition == .top {
                HStack(spacing: 8) {
                    systemTrayItems
                }
            } else {
                VStack(spacing: 8) {
                    systemTrayItems
                }
            }
        }
    }
    
    private var systemTrayItems: some View {
        Group {
            // Date & Time
            Text(currentTime)
                .font(.system(size: 12))
                .foregroundColor(.white)
            
            // Battery (if available)
            if let battery = getBatteryInfo() {
                HStack(spacing: 2) {
                    Image(systemName: battery.icon)
                        .font(.system(size: 12))
                    Text("\(battery.percentage)%")
                        .font(.system(size: 11))
                }
                .foregroundColor(.white)
            }
            
            // Network
            Image(systemName: "wifi")
                .font(.system(size: 12))
                .foregroundColor(.white)
            
            // Volume
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 12))
                .foregroundColor(.white)
        }
    }
    
    private var iconSize: CGFloat {
        useSmallTaskbarButtons ? dockSize.iconSize * 0.8 : dockSize.iconSize
    }
    
    private var currentTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
    }
    
    private func getBatteryInfo() -> (icon: String, percentage: Int)? {
        // This would need actual battery monitoring implementation
        return ("battery.75", 75)
    }
    
    private func showMissionControl() {
        let script = """
        tell application "System Events"
            key code 126 using {control down, shift down}
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
    
    private func openSpotlight() {
        // Trigger Spotlight with Command+Space
        let src = CGEventSource(stateID: .hidSystemState)
        let cmdd = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
        let cmdu = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        let spcd = CGEvent(keyboardEventSource: src, virtualKey: 0x31, keyDown: true)
        let spcu = CGEvent(keyboardEventSource: src, virtualKey: 0x31, keyDown: false)
        
        cmdd?.flags = .maskCommand
        spcd?.flags = .maskCommand
        
        let loc = CGEventTapLocation.cghidEventTap
        cmdd?.post(tap: loc)
        spcd?.post(tap: loc)
        spcu?.post(tap: loc)
        cmdu?.post(tap: loc)
    }
    
    private func openSearch() {
        switch searchAppChoice {
        case .spotlight:
            openSpotlight()
            
        case .raycast:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.raycast.macos") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } else {
                // Fallback to Spotlight if Raycast not installed
                openSpotlight()
            }
            
        case .alfred:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.runningwithcrayons.Alfred") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } else {
                // Fallback to Spotlight if Alfred not installed
                openSpotlight()
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        // Handle file drops
        return false
    }
    
    private func handleAppReorder(providers: [NSItemProvider], targetApp: DockApp) -> Bool {
        guard let draggedApp = self.draggedApp,
              draggedApp.id != targetApp.id else { return false }
        
        var apps = appManager.dockApps
        if let fromIndex = apps.firstIndex(where: { $0.id == draggedApp.id }),
           let toIndex = apps.firstIndex(where: { $0.id == targetApp.id }) {
            apps.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            appManager.dockApps = apps
            appManager.saveDockAppOrder()
        }
        
        return true
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