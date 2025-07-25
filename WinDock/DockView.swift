import SwiftUI
import AppKit

struct DockView: View {
    @StateObject private var appManager = AppManager()
    @State private var showingPreview = false
    @State private var previewWindow: NSWindow?
    @State private var showStartMenu = false
    @State private var dragOverIndex: Int? = nil
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

    @ViewBuilder
    private var dockIconsSection: some View {
        if dockPosition == .bottom || dockPosition == .top {
            HStack(spacing: 2) {
                ForEach(Array(appManager.dockApps.enumerated()), id: \.element.id) { index, app in
                    HStack(spacing: 0) {
                        // Insertion indicator before the icon
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 3, height: 40)
                            .opacity(dragOverIndex == index ? 0.8 : 0.0)
                            .animation(.easeInOut(duration: 0.2), value: dragOverIndex)
                        
                        WindowsTaskbarIcon(
                            app: app,
                            iconSize: dockSize.iconSize,
                            appManager: appManager
                        )
                    }
                    .onDrop(of: ["public.plain-text"], delegate: DockDropDelegate(
                        insertionIndex: index,
                        appManager: appManager,
                        onDragOver: { isOver in
                            dragOverIndex = isOver ? index : nil
                        }
                    ))
                }
                
                // Final drop zone after all icons
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 40)
                    .opacity(dragOverIndex == appManager.dockApps.count ? 0.8 : 0.0)
                    .animation(.easeInOut(duration: 0.2), value: dragOverIndex)
                    .onDrop(of: ["public.plain-text"], delegate: DockDropDelegate(
                        insertionIndex: appManager.dockApps.count,
                        appManager: appManager,
                        onDragOver: { isOver in
                            dragOverIndex = isOver ? appManager.dockApps.count : nil
                        }
                    ))
            }
        } else {
            VStack(spacing: 2) {
                ForEach(Array(appManager.dockApps.enumerated()), id: \.element.id) { index, app in
                    VStack(spacing: 0) {
                        // Insertion indicator before the icon
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 40, height: 3)
                            .opacity(dragOverIndex == index ? 0.8 : 0.0)
                            .animation(.easeInOut(duration: 0.2), value: dragOverIndex)
                        
                        WindowsTaskbarIcon(
                            app: app,
                            iconSize: dockSize.iconSize,
                            appManager: appManager
                        )
                    }
                    .onDrop(of: ["public.plain-text"], delegate: DockDropDelegate(
                        insertionIndex: index,
                        appManager: appManager,
                        onDragOver: { isOver in
                            dragOverIndex = isOver ? index : nil
                        }
                    ))
                }
                
                // Final drop zone after all icons
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 40, height: 3)
                    .opacity(dragOverIndex == appManager.dockApps.count ? 0.8 : 0.0)
                    .animation(.easeInOut(duration: 0.2), value: dragOverIndex)
                    .onDrop(of: ["public.plain-text"], delegate: DockDropDelegate(
                        insertionIndex: appManager.dockApps.count,
                        appManager: appManager,
                        onDragOver: { isOver in
                            dragOverIndex = isOver ? appManager.dockApps.count : nil
                        }
                    ))
            }
        }
    }
}

// Drop delegate for handling insertions between icons
struct DockDropDelegate: DropDelegate {
    let insertionIndex: Int
    let appManager: AppManager
    let onDragOver: (Bool) -> Void
    
    func validateDrop(info: DropInfo) -> Bool {
        // Check if the drop info contains plain text items
        let hasCompatibleItem = info.hasItemsConforming(to: ["public.plain-text"])
        AppLogger.shared.info("Validating drop - has compatible item: \(hasCompatibleItem)")
        return hasCompatibleItem
    }
    
    func dropEntered(info: DropInfo) {
        onDragOver(true)
    }
    
    func dropExited(info: DropInfo) {
        onDragOver(false)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        onDragOver(false)
        
        // Notify that drag has ended
        NotificationCenter.default.post(name: NSNotification.Name("DragEnded"), object: nil)
        
        let providers = info.itemProviders(for: ["public.plain-text"])
        guard let provider = providers.first else { 
            AppLogger.shared.error("No item provider found")
            return false 
        }
        
        AppLogger.shared.info("Loading item with public.plain-text type")
        
        provider.loadDataRepresentation(forTypeIdentifier: "public.plain-text") { (data, error) in
            if let error = error {
                AppLogger.shared.error("Error loading data: \(error)")
                return
            }
            
            guard let data = data,
                  let bundleIdentifier = String(data: data, encoding: .utf8) else {
                AppLogger.shared.error("Could not extract bundle identifier from data")
                return
            }
            
            AppLogger.shared.info("Processing drop for bundle identifier: \(bundleIdentifier)")
            
            DispatchQueue.main.async {
                let currentApps = appManager.dockApps
                guard let draggedApp = currentApps.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
                    AppLogger.shared.error("Could not find dragged app with bundle identifier: \(bundleIdentifier)")
                    AppLogger.shared.info("Available apps: \(currentApps.map { $0.bundleIdentifier })")
                    return
                }
                
                guard let fromIndex = currentApps.firstIndex(of: draggedApp) else {
                    AppLogger.shared.error("Could not find index of dragged app")
                    return
                }
                
                guard fromIndex != insertionIndex else {
                    AppLogger.shared.info("Drop at same position, ignoring")
                    return
                }
                
                AppLogger.shared.info("Moving app from index \(fromIndex) to insertion index \(insertionIndex)")
                
                // Calculate the correct insertion index
                let toIndex = fromIndex < insertionIndex ? insertionIndex - 1 : insertionIndex
                appManager.moveApp(from: fromIndex, to: toIndex)
            }
        }
        
        return true
    }
}