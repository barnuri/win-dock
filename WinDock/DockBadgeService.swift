import Foundation
import AppKit
import ApplicationServices

/// Thread-safe service for reading notification badge counts from Dock.app's accessibility tree.
/// On macOS, every app that sets `NSDockTile.badgeLabel` exposes its badge via `AXStatusLabel`
/// on the corresponding `AXApplicationDockItem` in Dock.app's AX hierarchy.
/// This is universal — no per-app AppleScript or hardcoded whitelist needed.
actor DockBadgeService {
    private var cachedBadges: [String: Int] = [:]
    private var cacheTimestamp: Date = .distantPast
    private let cacheDuration: TimeInterval = 5.0

    public init() {}

    /// Returns a dictionary mapping bundle identifiers to their badge counts.
    /// Uses a 5-second cache to avoid redundant AX tree traversals.
    public func getBadges() async -> [String: Int] {
        if Date().timeIntervalSince(cacheTimestamp) < cacheDuration {
            return cachedBadges
        }

        let badges = await readBadgesFromDock()
        cachedBadges = badges
        cacheTimestamp = Date()
        return badges
    }

    /// Returns the badge count for a specific bundle identifier, or 0 if none.
    public func getBadgeCount(for bundleIdentifier: String) async -> Int {
        let badges = await getBadges()
        return badges[bundleIdentifier] ?? 0
    }

    /// Invalidates the cached badge data, forcing a fresh read on next access.
    public func invalidateCache() {
        cacheTimestamp = .distantPast
    }

    // MARK: - Private Implementation

    /// Reads badge counts from Dock.app's accessibility tree in a background task.
    private func readBadgesFromDock() async -> [String: Int] {
        return await Task.detached(priority: .userInitiated) {
            Self.readDockAXTree()
        }.value
    }

    /// Traverses Dock.app's AX hierarchy to extract badge labels.
    /// Dock.app structure: AXApplication -> AXList -> [AXApplicationDockItem...]
    /// Each dock item has AXStatusLabel (the badge text) when a badge is set.
    nonisolated private static func readDockAXTree() -> [String: Int] {
        var result: [String: Int] = [:]

        // Find Dock.app process
        guard let dockApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock"
        ).first else {
            AppLogger.shared.debug("DockBadgeService: Dock.app not found")
            return result
        }

        let dockAX = AXUIElementCreateApplication(dockApp.processIdentifier)

        // Get Dock.app's children (should contain AXList elements)
        guard let children = getAXChildren(of: dockAX) else {
            AppLogger.shared.debug("DockBadgeService: Could not read Dock.app children")
            return result
        }

        // Traverse each child looking for AXList containing dock items
        for child in children {
            guard getAXRole(of: child) == "AXList" else { continue }

            guard let dockItems = getAXChildren(of: child) else { continue }

            for item in dockItems {
                guard getAXRole(of: item) == "AXDockItem",
                      let subrole = getAXSubrole(of: item),
                      subrole == "AXApplicationDockItem" else { continue }

                // Read the status label (badge text)
                guard let statusLabel = getAXStatusLabel(of: item),
                      !statusLabel.isEmpty else { continue }

                // Get the app's URL to resolve bundle identifier
                guard let appURL = getAXURL(of: item),
                      let bundle = Bundle(url: appURL),
                      let bundleId = bundle.bundleIdentifier else { continue }

                let count = parseBadgeText(statusLabel)
                if count > 0 {
                    result[bundleId] = count
                }
            }
        }

        AppLogger.shared.debug("DockBadgeService: Found \(result.count) badges")
        return result
    }

    /// Parses badge text into a numeric count.
    /// Handles: "3", "99+", "5 new items", non-numeric text -> 1
    nonisolated static func parseBadgeText(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }

        // Try direct integer parse: "3", "42"
        if let count = Int(trimmed) {
            return max(count, 0)
        }

        // Handle "99+" style
        let plusStripped = trimmed.replacingOccurrences(of: "+", with: "")
        if let count = Int(plusStripped) {
            return max(count, 0)
        }

        // Extract leading number from strings like "5 new items"
        let digits = trimmed.prefix(while: { $0.isNumber })
        if !digits.isEmpty, let count = Int(digits) {
            return max(count, 0)
        }

        // Non-numeric badge text (e.g. "New") → treat as 1
        return 1
    }

    // MARK: - AX Attribute Helpers

    nonisolated private static func getAXChildren(of element: AXUIElement) -> [AXUIElement]? {
        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard result == .success, let children = childrenRef as? [AXUIElement] else { return nil }
        return children
    }

    nonisolated private static func getAXRole(of element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        guard result == .success else { return nil }
        return roleRef as? String
    }

    nonisolated private static func getAXSubrole(of element: AXUIElement) -> String? {
        var subroleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        guard result == .success else { return nil }
        return subroleRef as? String
    }

    nonisolated private static func getAXStatusLabel(of element: AXUIElement) -> String? {
        var statusRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, "AXStatusLabel" as CFString, &statusRef)
        guard result == .success else { return nil }
        return statusRef as? String
    }

    nonisolated private static func getAXURL(of element: AXUIElement) -> URL? {
        var urlRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &urlRef)
        guard result == .success else { return nil }

        if let urlString = urlRef as? String {
            return URL(string: urlString)
        }
        if let url = urlRef as? URL {
            return url
        }
        if let cfURL = urlRef as! CFURL? {
            return cfURL as URL
        }
        return nil
    }
}
