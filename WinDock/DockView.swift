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
    
    // Computed property for background material - cached to avoid repeated calculations
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
            // Windows 11-style taskbar background with rounded corners and modern materials
            RoundedRectangle(cornerRadius: dockPosition == .bottom || dockPosition == .top ? 0 : 12)
                .fill(backgroundMaterial)
                .opacity(taskbarTransparency)
                .frame(width: geometry.size.width, height: 54)
                .overlay(
                    RoundedRectangle(cornerRadius: dockPosition == .bottom || dockPosition == .top ? 0 : 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.08),
                                    Color.clear,
                                    Color.black.opacity(0.03)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: dockPosition == .bottom || dockPosition == .top ? 0 : 12)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.clear,
                                    Color.black.opacity(0.08)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: dockPosition == .bottom ? -3 : 3)
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
                ForEach(appManager.dockApps, id: \.id) { app in
                    let index = appManager.dockApps.firstIndex(where: { $0.id == app.id }) ?? 0
                    HStack(spacing: 0) {
                        // Insertion indicator before the icon
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 3, height: 40)
                            .opacity(dragOverIndex == index ? 0.8 : 0.0)
                            .animation(.easeInOut(duration: 0.15), value: dragOverIndex)
                        
                        AppDockItem(
                            app: app,
                            iconSize: dockSize.iconSize,
                            appManager: appManager
                        )
                    }
                    .onDrop(of: ["public.plain-text", "com.windock.app-item"], delegate: DockDropDelegate(
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
                    .animation(.easeInOut(duration: 0.15), value: dragOverIndex)
                    .onDrop(of: ["public.plain-text", "com.windock.app-item"], delegate: DockDropDelegate(
                        insertionIndex: appManager.dockApps.count,
                        appManager: appManager,
                        onDragOver: { isOver in
                            dragOverIndex = isOver ? appManager.dockApps.count : nil
                        }
                    ))
            }
        } else {
            VStack(spacing: 2) {
                ForEach(appManager.dockApps, id: \.id) { app in
                    let index = appManager.dockApps.firstIndex(where: { $0.id == app.id }) ?? 0
                    VStack(spacing: 0) {
                        // Insertion indicator before the icon
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 40, height: 3)
                            .opacity(dragOverIndex == index ? 0.8 : 0.0)
                            .animation(.easeInOut(duration: 0.15), value: dragOverIndex)
                        
                        AppDockItem(
                            app: app,
                            iconSize: dockSize.iconSize,
                            appManager: appManager
                        )
                    }
                    .onDrop(of: ["public.plain-text", "com.windock.app-item"], delegate: DockDropDelegate(
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
                    .animation(.easeInOut(duration: 0.15), value: dragOverIndex)
                    .onDrop(of: ["public.plain-text", "com.windock.app-item"], delegate: DockDropDelegate(
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
        // Check if the drop info contains compatible items
        let hasCompatibleItem = info.hasItemsConforming(to: ["public.plain-text", "com.windock.app-item"])
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
        
        // Try custom app-item type first for more reliable data
        let providers = info.itemProviders(for: ["com.windock.app-item", "public.plain-text"])
        guard let provider = providers.first else { 
            AppLogger.shared.error("No item provider found")
            return false 
        }
        
        // Handle custom app-item type first
        if provider.hasItemConformingToTypeIdentifier("com.windock.app-item") {
            AppLogger.shared.info("Loading item with com.windock.app-item type")
            
            provider.loadDataRepresentation(forTypeIdentifier: "com.windock.app-item") { (data, error) in
                if let error = error {
                    AppLogger.shared.error("Error loading app-item data: \(error)")
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                      let bundleIdentifier = json["bundleIdentifier"] else {
                    AppLogger.shared.error("Could not extract bundle identifier from app-item data")
                    return
                }
                
                AppLogger.shared.info("Processing drop for bundle identifier from app-item: \(bundleIdentifier)")
                self.processDrop(bundleIdentifier: bundleIdentifier)
            }
        } else if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
            AppLogger.shared.info("Loading item with public.plain-text type")
            
            provider.loadDataRepresentation(forTypeIdentifier: "public.plain-text") { (data, error) in
                if let error = error {
                    AppLogger.shared.error("Error loading plain-text data: \(error)")
                    return
                }
                
                guard let data = data,
                      let bundleIdentifier = String(data: data, encoding: .utf8) else {
                    AppLogger.shared.error("Could not extract bundle identifier from plain-text data")
                    return
                }
                
                AppLogger.shared.info("Processing drop for bundle identifier from plain-text: \(bundleIdentifier)")
                self.processDrop(bundleIdentifier: bundleIdentifier)
            }
        }
        
        return true
    }
    
    private func processDrop(bundleIdentifier: String) {
        DispatchQueue.main.async {
            let currentApps = self.appManager.dockApps
            guard let draggedApp = currentApps.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
                AppLogger.shared.error("Could not find dragged app with bundle identifier: \(bundleIdentifier)")
                AppLogger.shared.info("Available apps: \(currentApps.map { $0.bundleIdentifier })")
                return
            }
            
            guard let fromIndex = currentApps.firstIndex(of: draggedApp) else {
                AppLogger.shared.error("Could not find index of dragged app")
                return
            }
            
            guard fromIndex != self.insertionIndex else {
                AppLogger.shared.info("Drop at same position, ignoring")
                return
            }
            
            AppLogger.shared.info("Moving app from index \(fromIndex) to insertion index \(self.insertionIndex)")
            
            // Calculate the correct insertion index
            let toIndex = fromIndex < self.insertionIndex ? self.insertionIndex - 1 : self.insertionIndex
            self.appManager.moveApp(from: fromIndex, to: toIndex)
        }
    }
}