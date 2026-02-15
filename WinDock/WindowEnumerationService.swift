import Foundation
import AppKit
import Accessibility
import ApplicationServices

/// Thread-safe service for enumerating application windows using Accessibility API.
/// All AX API calls are performed on background threads to prevent main thread blocking.
/// Implements 1-second caching to avoid redundant expensive operations.
actor WindowEnumerationService {
    private var windowCache: [pid_t: CachedWindows] = [:]
    
    struct CachedWindows {
        let windows: [WindowInfo]
        let timestamp: Date
        
        var isValid: Bool {
            Date().timeIntervalSince(timestamp) < 1.0
        }
    }
    
    public init() {}
    
    /// Retrieves windows for the given application, using cache when possible.
    /// All expensive AX API calls are performed on background threads.
    /// - Parameter app: The running application to enumerate windows for
    /// - Returns: Array of window information
    public func getWindows(for app: NSRunningApplication) async -> [WindowInfo] {
        let pid = app.processIdentifier
        
        // Check cache first (fast path)
        if let cached = windowCache[pid], cached.isValid {
            AppLogger.shared.debug("Cache hit for \(app.localizedName ?? "unknown") (pid: \(pid))")
            return cached.windows
        }
        
        // Cache miss or expired - enumerate windows in background
        AppLogger.shared.debug("Cache miss for \(app.localizedName ?? "unknown") (pid: \(pid)) - enumerating windows")
        
        let windows = await enumerateWindowsInBackground(pid: pid, app: app)
        
        // Cache the result
        windowCache[pid] = CachedWindows(windows: windows, timestamp: Date())
        
        return windows
    }
    
    /// Invalidates the cache for a specific application.
    /// - Parameter app: The application whose cache should be cleared
    public func invalidateCache(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        windowCache.removeValue(forKey: pid)
        AppLogger.shared.debug("Cache invalidated for pid: \(pid)")
    }
    
    /// Clears all cached window data.
    public func clearAllCaches() {
        windowCache.removeAll()
        AppLogger.shared.debug("All window caches cleared")
    }
    
    // MARK: - Private Implementation
    
    /// Enumerates windows in a background task to avoid main thread blocking.
    private func enumerateWindowsInBackground(pid: pid_t, app: NSRunningApplication) async -> [WindowInfo] {
        return await Task.detached(priority: .userInitiated) {
            await self.enumerateWindowsSync(pid: pid, app: app)
        }.value
    }
    
    /// Synchronous window enumeration - runs on background thread.
    /// This is where all the expensive AX API calls happen.
    private func enumerateWindowsSync(pid: pid_t, app: NSRunningApplication) async -> [WindowInfo] {
        // Create AXUIElement for the application
        let axApp = AXUIElementCreateApplication(pid)
        
        // Get AX windows using accessibility API
        let axWindows = await getAXWindows(axApp: axApp, pid: pid)
        
        // Get Core Graphics window info for additional details
        guard let cgWindowList = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            AppLogger.shared.warning("Failed to get CG window list for pid: \(pid)")
            return []
        }
        
        // Process windows concurrently for better performance
        return await processWindowsConcurrently(
            axWindows: axWindows,
            cgWindowList: cgWindowList,
            pid: pid,
            app: app
        )
    }
    
    /// Processes AX windows concurrently using structured concurrency.
    private func processWindowsConcurrently(
        axWindows: [AXUIElement],
        cgWindowList: [[String: Any]],
        pid: pid_t,
        app: NSRunningApplication
    ) async -> [WindowInfo] {
        return await withTaskGroup(of: WindowInfo?.self) { group in
            for axWindow in axWindows {
                group.addTask {
                    await self.processSingleWindow(
                        axWindow: axWindow,
                        cgWindowList: cgWindowList,
                        pid: pid,
                        app: app
                    )
                }
            }
            
            var windows: [WindowInfo] = []
            for await window in group {
                if let window = window {
                    windows.append(window)
                }
            }
            return windows
        }
    }
    
    /// Processes a single window, extracting all necessary information.
    private func processSingleWindow(
        axWindow: AXUIElement,
        cgWindowList: [[String: Any]],
        pid: pid_t,
        app: NSRunningApplication
    ) async -> WindowInfo? {
        // Get window ID through AX API
        guard let windowID = getWindowID(from: axWindow) else { return nil }
        
        // Get window attributes from AX API
        guard let windowAttributes = getWindowAttributes(from: axWindow) else { return nil }
        
        // Find matching CG window for additional info
        var cgWindowInfo: [String: Any]?
        for info in cgWindowList {
            if let cgWindowID = info[kCGWindowNumber as String] as? CGWindowID,
               cgWindowID == windowID,
               let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
               ownerPID == pid {
                cgWindowInfo = info
                break
            }
        }
        
        // Get bounds from CG info or calculate from AX
        let bounds: CGRect
        if let cgInfo = cgWindowInfo,
           let boundsDict = cgInfo[kCGWindowBounds as String] as? [String: Any],
           let cgBounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
            bounds = cgBounds
        } else {
            bounds = getWindowBounds(from: axWindow) ?? CGRect.zero
        }
        
        let isOnScreen = cgWindowInfo?[kCGWindowIsOnscreen as String] as? Bool ?? false
        let level = getWindowLevel(windowID: windowID)
        
        // Apply filtering logic using AX attributes
        guard isActualWindow(
            axWindow: axWindow,
            windowID: windowID,
            level: level,
            title: windowAttributes.title,
            subrole: windowAttributes.subrole,
            role: windowAttributes.role,
            size: bounds.size,
            isMinimized: windowAttributes.isMinimized,
            isFullscreen: windowAttributes.isFullscreen,
            app: app
        ) else {
            return nil
        }
        
        return WindowInfo(
            title: windowAttributes.title ?? "",
            windowID: windowID,
            bounds: bounds,
            isMinimized: windowAttributes.isMinimized,
            isOnScreen: isOnScreen
        )
    }
    
    // MARK: - AX API Helper Methods (nonisolated for background execution)
    
    /// Gets AX windows using accessibility API.
    nonisolated private func getAXWindows(axApp: AXUIElement, pid: pid_t) async -> [AXUIElement] {
        var axWindows: [AXUIElement] = []
        
        // Get windows using standard AX API
        var windowListRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowListRef)
        
        if result == .success, let windowList = windowListRef as? [AXUIElement] {
            axWindows.append(contentsOf: windowList)
        }
        
        // Also try brute-force approach for windows on other spaces
        axWindows.append(contentsOf: getWindowsByBruteForce(pid: pid))
        
        // Remove duplicates
        return Array(Set(axWindows))
    }
    
    /// Brute-force window detection for windows on other spaces.
    nonisolated private func getWindowsByBruteForce(pid: pid_t) -> [AXUIElement] {
        var axWindows: [AXUIElement] = []
        
        // Create remote token
        var remoteToken = Data(count: 20)
        remoteToken.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        remoteToken.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        remoteToken.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
        
        // Try different AXUIElementID values
        for axUiElementId: UInt in 0..<1000 {
            remoteToken.replaceSubrange(12..<20, with: withUnsafeBytes(of: axUiElementId) { Data($0) })
            
            if let axUiElement = _AXUIElementCreateWithRemoteToken(remoteToken as CFData)?.takeRetainedValue() {
                do {
                    if let subrole = try getSubrole(from: axUiElement),
                       [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole) {
                        axWindows.append(axUiElement)
                    }
                } catch {
                    // Ignore errors and continue
                }
            }
        }
        
        return axWindows
    }
    
    nonisolated private func getWindowID(from axWindow: AXUIElement) -> CGWindowID? {
        var windowID: CGWindowID = 0
        let result = _AXUIElementGetWindow(axWindow, &windowID)
        return result == .success ? windowID : nil
    }
    
    nonisolated private func getWindowAttributes(from axWindow: AXUIElement) -> WindowAttributes? {
        do {
            let title = try getTitle(from: axWindow)
            let role = try getRole(from: axWindow)
            let subrole = try getSubrole(from: axWindow)
            let isMinimized = try getIsMinimized(from: axWindow)
            let isFullscreen = try getIsFullscreen(from: axWindow)
            
            return WindowAttributes(
                title: title,
                role: role,
                subrole: subrole,
                isMinimized: isMinimized,
                isFullscreen: isFullscreen
            )
        } catch {
            return nil
        }
    }
    
    nonisolated private func getWindowBounds(from axWindow: AXUIElement) -> CGRect? {
        do {
            let position = try getPosition(from: axWindow)
            let size = try getSize(from: axWindow)
            
            if let pos = position, let sz = size {
                return CGRect(origin: pos, size: sz)
            }
        } catch {
            // Ignore errors
        }
        return nil
    }
    
    nonisolated private func getTitle(from axWindow: AXUIElement) throws -> String? {
        var titleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
        return result == .success ? (titleRef as? String) : nil
    }
    
    nonisolated private func getRole(from axWindow: AXUIElement) throws -> String? {
        var roleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axWindow, kAXRoleAttribute as CFString, &roleRef)
        return result == .success ? (roleRef as? String) : nil
    }
    
    nonisolated private func getSubrole(from axWindow: AXUIElement) throws -> String? {
        var subroleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &subroleRef)
        return result == .success ? (subroleRef as? String) : nil
    }
    
    nonisolated private func getIsMinimized(from axWindow: AXUIElement) throws -> Bool {
        var minimizedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef)
        return result == .success ? (minimizedRef as? Bool ?? false) : false
    }
    
    nonisolated private func getIsFullscreen(from axWindow: AXUIElement) throws -> Bool {
        var fullscreenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axWindow, kAXFullscreenAttribute as CFString, &fullscreenRef)
        return result == .success ? (fullscreenRef as? Bool ?? false) : false
    }
    
    nonisolated private func getPosition(from axWindow: AXUIElement) throws -> CGPoint? {
        var positionRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef)
        
        if result == .success, let axValue = positionRef {
            // Safely cast to AXValue instead of force unwrap
            guard CFGetTypeID(axValue) == AXValueGetTypeID() else {
                return nil
            }
            var point = CGPoint.zero
            if AXValueGetValue(axValue as! AXValue, .cgPoint, &point) {
                return point
            }
        }
        return nil
    }
    
    nonisolated private func getSize(from axWindow: AXUIElement) throws -> CGSize? {
        var sizeRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)
        
        if result == .success, let axValue = sizeRef {
            // Safely cast to AXValue instead of force unwrap
            guard CFGetTypeID(axValue) == AXValueGetTypeID() else {
                return nil
            }
            var size = CGSize.zero
            if AXValueGetValue(axValue as! AXValue, .cgSize, &size) {
                return size
            }
        }
        return nil
    }
    
    nonisolated private func getWindowLevel(windowID: CGWindowID) -> CGWindowLevel {
        var level: CGWindowLevel = 0
        let cgsConnection = CGSMainConnectionID()
        _ = CGSGetWindowLevel(cgsConnection, windowID, &level)
        return level
    }
    
    /// Determines if a window is an actual user window using AX attributes.
    nonisolated private func isActualWindow(
        axWindow: AXUIElement,
        windowID: CGWindowID,
        level: CGWindowLevel,
        title: String?,
        subrole: String?,
        role: String?,
        size: CGSize?,
        isMinimized: Bool,
        isFullscreen: Bool,
        app: NSRunningApplication
    ) -> Bool {
        let bundleID = app.bundleIdentifier ?? ""
        
        // Basic validity checks
        guard windowID > 0 else { return false }
        
        // Size constraints
        guard let windowSize = size,
              windowSize.width > 100 && windowSize.height > 50 else { return false }
        
        let normalLevel = CGWindowLevelForKey(.normalWindow)
        
        // Check for special app cases
        if isSpecialApp(bundleID: bundleID, title: title, role: role, subrole: subrole, level: level, size: windowSize) {
            return true
        }
        
        // Standard filtering for normal level windows
        if level == normalLevel {
            if let subrole = subrole, [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole) {
                return isValidStandardWindow(bundleID: bundleID, title: title, size: windowSize, subrole: subrole)
            }
        }
        
        // Floating windows (only for specific apps)
        if level == CGWindowLevelForKey(.floatingWindow) {
            return isValidFloatingWindow(bundleID: bundleID, title: title, role: role, subrole: subrole, size: windowSize)
        }
        
        return false
    }
    
    nonisolated private func isSpecialApp(bundleID: String, title: String?, role: String?, subrole: String?, level: CGWindowLevel, size: CGSize) -> Bool {
        let normalLevel = CGWindowLevelForKey(.normalWindow)
        
        // Known special cases
        if bundleID == "com.apple.iBooksX" { return true }
        if bundleID == "com.apple.iWork.Keynote" { return true }
        if bundleID == "com.colliderli.iina" { return true }
        
        if bundleID == "com.apple.Preview" {
            return level == normalLevel && subrole != nil && [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole!)
        }
        
        if (bundleID == "com.adobe.Audition" || bundleID == "com.adobe.AfterEffects") && subrole == kAXFloatingWindowSubrole {
            return true
        }
        
        if bundleID == "com.valvesoftware.steam" {
            return title != nil && !title!.isEmpty && role != nil
        }
        
        if bundleID == "com.blizzard.worldofwarcraft" && role == kAXWindowRole {
            return true
        }
        
        if bundleID == "net.battle.bootstrapper" && role == kAXWindowRole {
            return true
        }
        
        if bundleID.hasPrefix("org.mozilla.firefox") && role == kAXWindowRole && size.height > 400 {
            return true
        }
        
        if bundleID.hasPrefix("org.videolan.vlc") && role == kAXWindowRole {
            return true
        }
        
        if bundleID.hasPrefix("com.autodesk.AutoCAD") && subrole == "AXDocumentWindow" {
            return true
        }
        
        if bundleID.hasPrefix("com.jetbrains.") || bundleID.hasPrefix("com.google.android.studio") {
            return title != nil && !title!.isEmpty && size.width > 100 && size.height > 100
        }
        
        return false
    }
    
    nonisolated private func isValidStandardWindow(bundleID: String, title: String?, size: CGSize, subrole: String) -> Bool {
        if bundleID.hasPrefix("com.jetbrains.") || bundleID.hasPrefix("com.google.android.studio") {
            return title != nil && !title!.isEmpty && size.width > 100 && size.height > 100
        }
        
        if bundleID == "com.IdeaPunch.ColorSlurp" {
            return subrole == kAXStandardWindowSubrole
        }
        
        return true
    }
    
    nonisolated private func isValidFloatingWindow(bundleID: String, title: String?, role: String?, subrole: String?, size: CGSize) -> Bool {
        if bundleID == "com.colliderli.iina" { return true }
        
        if (bundleID == "com.adobe.Audition" || bundleID == "com.adobe.AfterEffects") && subrole == kAXFloatingWindowSubrole {
            return true
        }
        
        if bundleID.isEmpty && role == kAXWindowRole && subrole == kAXStandardWindowSubrole {
            return true
        }
        
        return false
    }
}
