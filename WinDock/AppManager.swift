import Foundation
import AppKit
import Combine
import Accessibility
import ApplicationServices

// Private API declarations
@_silgen_name("CGSGetWindowLevel")
func CGSGetWindowLevel(_ cid: CGSConnectionID, _ wid: CGWindowID, _ level: UnsafeMutablePointer<CGWindowLevel>) -> CGError

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("_AXUIElementCreateWithRemoteToken")
func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?

// SkyLight private APIs for window focusing (same approach as alt-tab-macos)
@_silgen_name("_SLPSSetFrontProcessWithOptions") @discardableResult
func _SLPSSetFrontProcessWithOptions(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ wid: CGWindowID, _ mode: UInt32) -> CGError

@_silgen_name("SLPSPostEventRecordTo") @discardableResult
func SLPSPostEventRecordTo(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError

// GetProcessForPID is deprecated and unavailable in Swift, but still works at runtime
@_silgen_name("GetProcessForPID") @discardableResult
func getProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

enum SLPSMode: UInt32 {
    case allWindows = 0x100
    case userGenerated = 0x200
    case noWindows = 0x400
}

// Missing AX attribute constants
let kAXFullscreenAttribute = "AXFullScreen" as CFString

// MARK: - Window Focus Helpers (Private API approach, like alt-tab-macos)
// These replace AppleScript-based activation to avoid "Choose Application" popups

/// Focus a window using private macOS APIs
private func focusWindowWithPrivateAPIs(windowID: CGWindowID, pid: pid_t) {
    var psn = ProcessSerialNumber()
    getProcessForPID(pid, &psn)
    _SLPSSetFrontProcessWithOptions(&psn, windowID, SLPSMode.userGenerated.rawValue)
    makeWindowKey(windowID: windowID, psn: &psn)
    raiseWindowViaAX(windowID: windowID, pid: pid)
}

/// Make a window the key window using SLPSPostEventRecordTo
/// Ported from https://github.com/Hammerspoon/hammerspoon/issues/370#issuecomment-545545468
private func makeWindowKey(windowID: CGWindowID, psn: inout ProcessSerialNumber) {
    var bytes = [UInt8](repeating: 0, count: 0xf8)
    bytes[0x04] = 0xf8
    bytes[0x3a] = 0x10
    var wid = windowID
    memcpy(&bytes[0x3c], &wid, MemoryLayout<UInt32>.size)
    memset(&bytes[0x20], 0xff, 0x10)
    bytes[0x08] = 0x01
    SLPSPostEventRecordTo(&psn, &bytes)
    bytes[0x08] = 0x02
    SLPSPostEventRecordTo(&psn, &bytes)
}

/// Raise a window using AXUIElement kAXRaiseAction
private func raiseWindowViaAX(windowID: CGWindowID, pid: pid_t) {
    let axApp = AXUIElementCreateApplication(pid)
    var windowElements: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowElements) == .success,
          let windows = windowElements as? [AXUIElement] else { return }
    for window in windows {
        var wid: CGWindowID = 0
        if _AXUIElementGetWindow(window, &wid) == .success, wid == windowID {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            break
        }
    }
}

/// Unminimize a specific window by ID using AX API
private func unminimizeWindowByID(_ windowID: CGWindowID, pid: pid_t) {
    let axApp = AXUIElementCreateApplication(pid)
    var windowElements: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowElements) == .success,
          let windows = windowElements as? [AXUIElement] else { return }
    for window in windows {
        var wid: CGWindowID = 0
        if _AXUIElementGetWindow(window, &wid) == .success, wid == windowID {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            break
        }
    }
}

/// Unminimize all windows for an app using AX API
private func unminimizeAllWindowsAX(pid: pid_t) {
    let axApp = AXUIElementCreateApplication(pid)
    var windowElements: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowElements) == .success,
          let windows = windowElements as? [AXUIElement] else { return }
    for window in windows {
        var isMinimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMinimized) == .success,
           let minimized = isMinimized as? Bool, minimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
        }
    }
}

/// Get the frontmost window ID for an app using AX API
private func getFrontWindowID(pid: pid_t) -> CGWindowID? {
    let axApp = AXUIElementCreateApplication(pid)
    var windowElements: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowElements) == .success,
          let windows = windowElements as? [AXUIElement], !windows.isEmpty else { return nil }
    var wid: CGWindowID = 0
    if _AXUIElementGetWindow(windows[0], &wid) == .success, wid > 0 {
        return wid
    }
    return nil
}

/// Close a window using AX API close button
private func closeWindowViaAX(windowID: CGWindowID, pid: pid_t) -> Bool {
    let axApp = AXUIElementCreateApplication(pid)
    var windowElements: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowElements) == .success,
          let windows = windowElements as? [AXUIElement] else { return false }
    for window in windows {
        var wid: CGWindowID = 0
        if _AXUIElementGetWindow(window, &wid) == .success, wid == windowID {
            var closeButton: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &closeButton) == .success {
                return AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString) == .success
            }
        }
    }
    return false
}

// Window attributes structure to hold AX API results
struct WindowAttributes {
    let title: String?
    let role: String?
    let subrole: String?
    let isMinimized: Bool
    let isFullscreen: Bool
}

struct WindowPreview {
    let windowID: CGWindowID
    let title: String
    let image: NSImage
    let bounds: CGRect
    let isMinimized: Bool
}

struct DockApp: Identifiable, Hashable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let name: String
    let icon: NSImage?
    let url: URL?
    var isPinned: Bool
    var runningApplication: NSRunningApplication?
    var windows: [WindowInfo] = []
    var notificationCount: Int = 0
    var hasNotifications: Bool = false

    var windowCount: Int {
        return windows.count
    }

    var isActive: Bool {
        return runningApplication?.isActive == true
    }

    var hasWindows: Bool { 
        return windows.count > 0
    }

    var isRunning: Bool {
        return runningApplication != nil
    }
    
    var isMinimized: Bool {
        guard let runningApp = runningApplication else { return false }
        // An app is considered minimized if it has windows but none are visible
        return isRunning && !runningApp.isActive && windows.allSatisfy { $0.isMinimized }
    }
    
    var isHidden: Bool {
        return runningApplication?.isHidden ?? false
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }
    
    static func == (lhs: DockApp, rhs: DockApp) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}

struct WindowInfo {
    let title: String
    let windowID: CGWindowID
    let bounds: CGRect
    let isMinimized: Bool
    let isOnScreen: Bool
}

@MainActor
class AppManager: ObservableObject {
    @Published var dockApps: [DockApp] = []

    private var appMonitorTimer: Timer?
    private var workspaceNotificationObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private let pinnedAppsKey = "WinDock.PinnedApps"
    private let dockAppOrderKey = "WinDock.DockAppOrder"
    private var pinnedBundleIdentifiers: Set<String> = []
    private var dockAppOrder: [String] = []
    // Note: Icons are cached in DockApp structures, not separately
    private var windowAttributesCache: [CGWindowID: WindowAttributes] = [:]
    
    // New services for performance optimization
    private let coordinator = BackgroundTaskCoordinator()
    private let windowService = WindowEnumerationService()
    private let badgeService = DockBadgeService()
    private var badgeRefreshTimer: Timer?
    // Monotonically increasing version; only the most-recently-started update writes dockApps.
    private var updateVersion: Int = 0

    // Default pinned applications - Windows 11 style defaults
    private let defaultPinnedApps = [
        "com.apple.finder",          // File Explorer equivalent
        "com.apple.Safari",           // Edge equivalent
        "com.apple.systempreferences", // Settings
        "com.apple.mail",             // Mail
        "com.apple.launchpad"         // Start menu equivalent
    ]
    
    // Bundle ID for WinDock itself
    private let winDockBundleID = Bundle.main.bundleIdentifier ?? "com.windock.app"

    init() {
        loadPinnedApps()
        loadDockAppOrder()
        setupWorkspaceNotifications()
        // Initial update through coordinator
        coordinator.scheduleUpdate(reason: "initial_load")
        startBadgeRefreshTimer()
    }
    
    deinit {
        Task { @MainActor [weak self] in
            self?.stopMonitoring()
        }
        badgeRefreshTimer?.invalidate()
        workspaceNotificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        cancellables.removeAll()
    }

    func hideOtherApps(except app: DockApp) {
        let runningApps = NSWorkspace.shared.runningApplications
        for runningApp in runningApps {
            guard runningApp.bundleIdentifier != app.bundleIdentifier,
                  runningApp.bundleIdentifier != winDockBundleID,
                  runningApp.activationPolicy == .regular,
                  runningApp.isHidden == false else { continue }
            runningApp.hide()
        }
    }

    func closeAllWindows(for app: DockApp) {
        guard let runningApp = app.runningApplication else { return }
        runningApp.terminate()
    }

    private func setupWorkspaceNotifications() {
        // Listen for PerformDockUpdate notification from coordinator
        let updateObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PerformDockUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDockApps()
            }
        }
        workspaceNotificationObservers.append(updateObserver)
        
        // Use workspace notifications instead of polling for better performance
        let workspace = NSWorkspace.shared
        let center = workspace.notificationCenter
        
        // App launch notification
        let launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.badgeService.invalidateCache()
                self?.coordinator.scheduleUpdate(reason: "app_launch")
            }
        }
        workspaceNotificationObservers.append(launchObserver)
        
        // App terminate notification
        let terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Invalidate caches for terminated app
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                Task { [weak self] in
                    await self?.windowService.invalidateCache(for: app)
                    await self?.badgeService.invalidateCache()
                }
            }
            Task { @MainActor [weak self] in
                self?.coordinator.scheduleUpdate(reason: "app_terminate")
            }
        }
        workspaceNotificationObservers.append(terminateObserver)
        
        // App activate notification — invalidate per-app window cache so the next
        // dock update picks up any windows opened since the last enumeration.
        // Invalidation and scheduling are sequenced in one Task to guarantee
        // the cache is cleared before getWindows() is called by the update.
        let activateObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { [weak self] in
                if let app { await self?.windowService.invalidateCache(for: app) }
                await MainActor.run { self?.coordinator.scheduleUpdate(reason: "app_activate") }
            }
        }
        workspaceNotificationObservers.append(activateObserver)

        // App hide/unhide notifications
        let hideObserver = center.addObserver(
            forName: NSWorkspace.didHideApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { [weak self] in
                if let app { await self?.windowService.invalidateCache(for: app) }
                await MainActor.run { self?.coordinator.scheduleUpdate(reason: "app_hide") }
            }
        }
        workspaceNotificationObservers.append(hideObserver)

        let unhideObserver = center.addObserver(
            forName: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { [weak self] in
                if let app { await self?.windowService.invalidateCache(for: app) }
                await MainActor.run { self?.coordinator.scheduleUpdate(reason: "app_unhide") }
            }
        }
        workspaceNotificationObservers.append(unhideObserver)
    }
    
    // Debouncing now handled by BackgroundTaskCoordinator
    // This method kept for backward compatibility but delegates to coordinator
    private func updateDockAppsDebounced() {
        coordinator.scheduleUpdate(reason: "legacy_call")
    }
    
    func startMonitoring() {
        // Initial update through coordinator
        coordinator.scheduleUpdate(reason: "start_monitoring")
        
        // Polling timer removed - rely entirely on notification-based updates
        // The coordinator handles all debouncing and batching
    }
    
    func stopMonitoring() {
        appMonitorTimer?.invalidate()
        appMonitorTimer = nil
        badgeRefreshTimer?.invalidate()
        badgeRefreshTimer = nil
        coordinator.cancelPendingUpdates()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func startBadgeRefreshTimer() {
        badgeRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshBadges()
            }
        }
    }

    /// Lightweight badge-only update — reads Dock.app's AX tree and updates
    /// only the notificationCount/hasNotifications fields on existing dockApps.
    /// Does NOT re-enumerate windows or trigger a full dock update.
    private func refreshBadges() async {
        let badges = await badgeService.getBadges()

        var changed = false
        for i in dockApps.indices {
            let newCount = badges[dockApps[i].bundleIdentifier] ?? 0
            let newHas = newCount > 0
            if dockApps[i].notificationCount != newCount || dockApps[i].hasNotifications != newHas {
                dockApps[i].notificationCount = newCount
                dockApps[i].hasNotifications = newHas
                changed = true
            }
        }

        if changed {
            AppLogger.shared.debug("Badge refresh: updated badges for \(badges.count) apps")
        }
    }
    
    // Public function to trigger update from outside
    func updateDockAppsIfNeeded() {
        coordinator.scheduleUpdate(reason: "external_request")
    }
    
    private func updateDockApps() {
        Task { @MainActor in
            await updateDockAppsAsync()
        }
    }
    
    private func updateDockAppsAsync() async {
        updateVersion &+= 1
        let myVersion = updateVersion
        let newDockApps = await computeDockApps()
        // Discard if a newer update has since started (prevents stale writes from slow
        // concurrent computations overwriting a more recent result).
        guard updateVersion == myVersion else {
            AppLogger.shared.debug("Discarding stale dock update (superseded by version \(updateVersion))")
            return
        }
        dockApps = newDockApps
    }
    
    // REMOVED @MainActor - this now runs on background thread
    private func computeDockApps() async -> [DockApp] {
        // Capture main actor values before going to background thread
        let pinnedIds = pinnedBundleIdentifiers
        let winDockId = winDockBundleID
        
        // Move to background thread immediately to avoid blocking UI
        return await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return [] }
            
            // Performance: Cache running apps to avoid multiple queries
            let runningApps = NSWorkspace.shared.runningApplications
                .filter { app in
                    // Filter out WinDock itself and only show regular apps
                    app.activationPolicy == .regular && 
                    app.bundleIdentifier != winDockId
                }

            var newDockApps: [DockApp] = []
            var processedBundleIds: Set<String> = []

            // Use concurrent processing for heavy operations
            await withTaskGroup(of: DockApp?.self) { group in
                for app in runningApps {
                    guard let bundleId = app.bundleIdentifier,
                          !processedBundleIds.contains(bundleId) else { continue }

                    processedBundleIds.insert(bundleId)
                    
                    group.addTask { [weak self] in
                        await self?.createDockApp(for: app, bundleId: bundleId)
                    }
                }
                
                for await dockApp in group {
                    if let app = dockApp {
                        newDockApps.append(app)
                    }
                }
            }

            // Add pinned apps that aren't running (lightweight operation)
            for bundleId in pinnedIds {
                if !processedBundleIds.contains(bundleId) {
                    if let app = await self.createDockAppForBundleIdAsync(bundleId) {
                        newDockApps.append(app)
                    }
                }
            }

            // Reorder based on saved order
            await self.reorderAppsAsync(&newDockApps)
            return newDockApps
        }.value
    }
    
    private func createDockApp(for app: NSRunningApplication, bundleId: String) async -> DockApp? {
        // Use WindowEnumerationService (async, off main thread)
        let windows = await windowService.getWindows(for: app)
        let (hasNotifications, notificationCount) = await getNotificationInfoAsync(for: app)

        return DockApp(
            bundleIdentifier: bundleId,
            name: app.localizedName ?? bundleId,
            icon: app.icon,
            url: app.bundleURL,
            isPinned: pinnedBundleIdentifiers.contains(bundleId),
            runningApplication: app,
            windows: windows,
            notificationCount: notificationCount,
            hasNotifications: hasNotifications
        )
    }
    
    private func reorderApps(_ apps: inout [DockApp]) {
        if !dockAppOrder.isEmpty {
            apps.sort { lhs, rhs in
                let lidx = dockAppOrder.firstIndex(of: lhs.bundleIdentifier) ?? Int.max
                let ridx = dockAppOrder.firstIndex(of: rhs.bundleIdentifier) ?? Int.max
                if lidx != ridx {
                    return lidx < ridx
                }
                // Fallback: pinned first, then by name
                if lhs.isPinned && !rhs.isPinned {
                    return true
                } else if !lhs.isPinned && rhs.isPinned {
                    return false
                } else {
                    return lhs.name < rhs.name
                }
            }
        } else {
            // Default ordering: pinned first, then by name
            apps.sort { lhs, rhs in
                if lhs.isPinned && !rhs.isPinned {
                    return true
                } else if !lhs.isPinned && rhs.isPinned {
                    return false
                } else {
                    return lhs.name < rhs.name
                }
            }
        }
    }
    
    // Async wrapper for reorderApps to access from background thread
    private func reorderAppsAsync(_ apps: inout [DockApp]) async {
        let order = dockAppOrder
        
        if !order.isEmpty {
            apps.sort { lhs, rhs in
                let lidx = order.firstIndex(of: lhs.bundleIdentifier) ?? Int.max
                let ridx = order.firstIndex(of: rhs.bundleIdentifier) ?? Int.max
                if lidx != ridx {
                    return lidx < ridx
                }
                // Fallback: pinned first, then by name
                if lhs.isPinned && !rhs.isPinned {
                    return true
                } else if !lhs.isPinned && rhs.isPinned {
                    return false
                } else {
                    return lhs.name < rhs.name
                }
            }
        } else {
            // Default ordering: pinned first, then by name
            apps.sort { lhs, rhs in
                if lhs.isPinned && !rhs.isPinned {
                    return true
                } else if !lhs.isPinned && rhs.isPinned {
                    return false
                } else {
                    return lhs.name < rhs.name
                }
            }
        }
    }
    
    
    
    // MARK: - Dock App Order Persistence

    private func loadDockAppOrder() {
        if let saved = UserDefaults.standard.array(forKey: dockAppOrderKey) as? [String] {
            dockAppOrder = saved
        } else {
            dockAppOrder = []
        }
    }

    func saveDockAppOrder() {
        let order = dockApps.map { $0.bundleIdentifier }
        UserDefaults.standard.set(order, forKey: dockAppOrderKey)
        dockAppOrder = order
    }
    
    private func createDockAppForBundleId(_ bundleId: String) -> DockApp? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
              let bundle = Bundle(url: appURL) else {
            return nil
        }
        
        let name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String ??
                   bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
                   bundle.infoDictionary?["CFBundleName"] as? String ??
                   bundleId
        
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        
        return DockApp(
            bundleIdentifier: bundleId,
            name: name,
            icon: icon,
            url: appURL,
            isPinned: true,
            runningApplication: nil,
            windows: [],
            notificationCount: 0,
            hasNotifications: false
        )
    }
    
    // Async wrapper for createDockAppForBundleId to access from background thread
    private func createDockAppForBundleIdAsync(_ bundleId: String) async -> DockApp? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
              let bundle = Bundle(url: appURL) else {
            return nil
        }
        
        let name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String ??
                   bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
                   bundle.infoDictionary?["CFBundleName"] as? String ??
                   bundleId
        
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)

        let isPinned = pinnedBundleIdentifiers.contains(bundleId)

        return DockApp(
            bundleIdentifier: bundleId,
            name: name,
            icon: icon,
            url: appURL,
            isPinned: isPinned,
            runningApplication: nil,
            windows: [],
            notificationCount: 0,
            hasNotifications: false
        )
    }
    
    // MARK: - Drag and Drop Reordering
    
    func moveApp(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < dockApps.count,
              destinationIndex >= 0, destinationIndex <= dockApps.count,
              sourceIndex != destinationIndex else { return }
        
        let app = dockApps.remove(at: sourceIndex)
        let insertIndex = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        dockApps.insert(app, at: insertIndex)
        NotificationCenter.default.post(name: NSNotification.Name("DockAppOrderChanged"), object: nil)
        AppLogger.shared.info("Moved app from index \(sourceIndex) to \(destinationIndex)")
        
        saveDockAppOrder()
    }
    
    func reorderApp(withBundleId sourceBundleId: String, toPosition targetApp: DockApp) {
        guard let sourceIndex = dockApps.firstIndex(where: { $0.bundleIdentifier == sourceBundleId }),
              let targetIndex = dockApps.firstIndex(where: { $0.bundleIdentifier == targetApp.bundleIdentifier }),
              sourceIndex != targetIndex else { return }
        
        moveApp(from: sourceIndex, to: targetIndex)
        AppLogger.shared.info("Reordered app \(sourceBundleId) to position of \(targetApp.name)")
    }
    
    // MARK: - App Actions

    func focusWindow(windowID: CGWindowID, app: DockApp) {
        guard let runningApp = app.runningApplication else {
            AppLogger.shared.warning("Cannot focus window: app is not running")
            return
        }

        AppLogger.shared.info("Focusing window \(windowID) for app \(app.name)")
        let pid = runningApp.processIdentifier

        // Step 1: Unhide the app if hidden
        if runningApp.isHidden {
            runningApp.unhide()
        }

        // Step 2: Focus using private APIs on background queue (no AppleScript)
        if windowID > 0 {
            DispatchQueue.global(qos: .userInitiated).async {
                unminimizeWindowByID(windowID, pid: pid)
                focusWindowWithPrivateAPIs(windowID: windowID, pid: pid)
            }
        } else {
            // No specific window, just activate the app
            if #available(macOS 14.0, *) {
                runningApp.activate()
            } else {
                runningApp.activate(options: [.activateAllWindows])
            }
        }
    }
    
    func closeWindow(windowID: CGWindowID, windowTitle: String, app: DockApp) -> Bool {
        guard let runningApp = app.runningApplication else {
            AppLogger.shared.warning("Cannot close window: app is not running")
            return false
        }
        
        AppLogger.shared.info("Closing window '\(windowTitle)' (ID: \(windowID)) for app \(app.name)")
        
        // Verify the window belongs to this app
        if windowID > 0 {
            guard let windowList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
                  let windowInfo = windowList.first,
                  let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == runningApp.processIdentifier else {
                AppLogger.shared.warning("Window \(windowID) does not belong to app \(app.name)")
                return false
            }
        }
        
        // Try multiple approaches for closing the window
        let processName = runningApp.localizedName ?? app.name
        var success = false
        
        // Approach 1: Use AX API to press close button (avoids "Choose Application" popup)
        if windowID > 0 {
            if closeWindowViaAX(windowID: windowID, pid: runningApp.processIdentifier) {
                AppLogger.shared.info("Successfully closed window using AX API")
                return true
            }
        }
        
        // Approach 2: System Events with accessibility actions
        let systemScript = """
        tell application "System Events"
            try
                tell process "\(processName)"
                    if "\(windowTitle)" is not "" then
                        try
                            set targetWindow to first window whose title is "\(windowTitle)"
                            click (first button of targetWindow whose subrole is "AXCloseButton")
                            return true
                        on error
                            -- Try alternative close methods
                            try
                                close window "\(windowTitle)"
                                return true
                            end try
                        end try
                    else
                        -- No window title, try to close first window
                        if (count windows) > 0 then
                            try
                                click (first button of window 1 whose subrole is "AXCloseButton")
                                return true
                            on error
                                try
                                    close window 1
                                    return true
                                end try
                            end try
                        end if
                    end if
                end tell
            end try
            return false
        end tell
        """
        
        if let systemAppleScript = NSAppleScript(source: systemScript) {
            var error: NSDictionary?
            let result = systemAppleScript.executeAndReturnError(&error)
            if error == nil, result.booleanValue {
                AppLogger.shared.info("Successfully closed window using System Events")
                success = true
            } else {
                AppLogger.shared.warning("System Events close failed: \(error?.description ?? "unknown")")
            }
        }
        
        // Approach 3: Fallback using keyboard shortcut (Cmd+W)
        if !success {
            let keyboardScript = """
            tell application "System Events"
                try
                    tell process "\(processName)"
                        set frontmost to true
                        if "\(windowTitle)" is not "" then
                            try
                                set targetWindow to first window whose title is "\(windowTitle)"
                                click targetWindow
                                delay 0.1
                            end try
                        end if
                        keystroke "w" using command down
                        return true
                    end tell
                on error
                    return false
                end try
            end tell
            """
            
            if let keyboardAppleScript = NSAppleScript(source: keyboardScript) {
                var error: NSDictionary?
                let result = keyboardAppleScript.executeAndReturnError(&error)
                if error == nil, result.booleanValue {
                    AppLogger.shared.info("Successfully closed window using keyboard shortcut")
                    success = true
                } else {
                    AppLogger.shared.warning("Keyboard shortcut close failed: \(error?.description ?? "unknown")")
                }
            }
        }
        
        if !success {
            AppLogger.shared.error("All window close attempts failed for window '\(windowTitle)'")
        }
        
        return success
    }

    func activateApp(_ app: DockApp) {
        AppLogger.shared.info("activateApp called for \(app.name), isRunning: \(app.isRunning), isActive: \(app.runningApplication?.isActive ?? false)")

        if let runningApp = app.runningApplication {
            let pid = runningApp.processIdentifier

            // Step 1: Unhide the app
            if runningApp.isHidden {
                runningApp.unhide()
            }

            // Step 2: Use private APIs to focus the app's front window (no AppleScript)
            DispatchQueue.global(qos: .userInitiated).async {
                // Unminimize all windows
                unminimizeAllWindowsAX(pid: pid)

                // Find and focus the frontmost window
                if let frontWindowID = getFrontWindowID(pid: pid) {
                    focusWindowWithPrivateAPIs(windowID: frontWindowID, pid: pid)
                } else {
                    // No AX windows found, fall back to NSRunningApplication.activate()
                    DispatchQueue.main.async {
                        if #available(macOS 14.0, *) {
                            runningApp.activate()
                        } else {
                            runningApp.activate(options: [.activateAllWindows])
                        }
                    }
                }
            }
        } else {
            // App not running, launch it
            AppLogger.shared.info("App \(app.name) not running, launching...")
            launchApp(app)
        }
    }
    
    func launchApp(_ app: DockApp) {
        if let appURL = app.url ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.promptsUserIfNeeded = false  // Prevent permission prompts
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error = error {
                    AppLogger.shared.error("Failed to launch \(app.name): \(error)")
                } else {
                    AppLogger.shared.info("Successfully launched \(app.name)")
                }
            }
        }
    }
    
    func cycleWindows(for app: DockApp) {
        guard app.runningApplication != nil else { return }
        
        // Use AppleScript to cycle through windows
        let script = """
        tell application "System Events"
            tell process "\(app.name)"
                if (count of windows) > 1 then
                    set frontmost to true
                    click menu item "Cycle Through Windows" of menu "Window" of menu bar 1
                end if
            end tell
        end tell
        """
        
        AppLogger.executeAppleScript(script, description: "Launch app \(app.name)")
    }
    
    func hideApp(_ app: DockApp) {
        AppLogger.shared.info("hideApp called for \(app.name), isRunning: \(app.isRunning), isActive: \(app.runningApplication?.isActive ?? false)")
        if let runningApp = app.runningApplication {
            runningApp.hide()
            AppLogger.shared.info("hideApp: hide() called for \(app.name)")
        } else {
            AppLogger.shared.error("hideApp: No runningApplication for \(app.name)")
        }
    }
    
    func quitApp(_ app: DockApp) {
        app.runningApplication?.terminate()
    }
    
    func showAllWindows(for app: DockApp) {
        if let runningApp = app.runningApplication {
            // Unhide the app if it's hidden
            if runningApp.isHidden {
                runningApp.unhide()
            }
            
            // Activate the app and show all windows
            if #available(macOS 14.0, *) {
                runningApp.activate()
            } else {
                runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
            
            // Show Exposé for this app
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let script = """
                tell application "System Events"
                    tell process "\(app.name)"
                        set frontmost to true
                    end tell
                    key code 101 using {control down}
                end tell
                """
                
                if let appleScript = NSAppleScript(source: script) {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                }
            }
        }
    }
    
    func launchNewInstance(_ app: DockApp) {
        if let appURL = app.url ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.promptsUserIfNeeded = false  // Prevent permission prompts
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        }
    }
    
    func pinApp(_ app: DockApp) {
        pinnedBundleIdentifiers.insert(app.bundleIdentifier)
        savePinnedApps()
        updateDockApps()
    }
    
    func unpinApp(_ app: DockApp) {
        pinnedBundleIdentifiers.remove(app.bundleIdentifier)
        savePinnedApps()
        updateDockApps()
    }
    
    // MARK: - Persistence
    
    private func loadPinnedApps() {
        if let saved = UserDefaults.standard.array(forKey: pinnedAppsKey) as? [String] {
            pinnedBundleIdentifiers = Set(saved)
        } else {
            // First launch - use default pinned apps
            pinnedBundleIdentifiers = Set(defaultPinnedApps)
            savePinnedApps()
        }
    }
    
    private func savePinnedApps() {
        UserDefaults.standard.set(Array(pinnedBundleIdentifiers), forKey: pinnedAppsKey)
    }
    
    private func getNotificationInfoAsync(for app: NSRunningApplication) async -> (hasNotifications: Bool, notificationCount: Int) {
        guard let bundleIdentifier = app.bundleIdentifier else {
            return (false, 0)
        }
        let count = await badgeService.getBadgeCount(for: bundleIdentifier)
        return (count > 0, count)
    }
}