import AppKit

/// Process-wide cache of app icons keyed by bundle identifier.
/// NSCache is thread-safe and evicts automatically under memory pressure.
final class IconCache: @unchecked Sendable {
    static let shared = IconCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 200
    }

    /// Returns the icon for a running application, caching by bundle identifier.
    func icon(for app: NSRunningApplication) -> NSImage? {
        guard let bundleId = app.bundleIdentifier else { return app.icon }
        return cachedIcon(bundleId: bundleId) { app.icon }
    }

    /// Returns the icon for an app at the given URL, caching by bundle identifier.
    func icon(forBundleId bundleId: String, appURL: URL) -> NSImage {
        // NSWorkspace always returns an image (generic doc icon at worst), so fetch never fails.
        cachedIcon(bundleId: bundleId) { NSWorkspace.shared.icon(forFile: appURL.path) }!
    }

    private func cachedIcon(bundleId: String, fetch: () -> NSImage?) -> NSImage? {
        if let cached = cache.object(forKey: bundleId as NSString) {
            return cached
        }
        guard let icon = fetch() else { return nil }
        cache.setObject(icon, forKey: bundleId as NSString)
        return icon
    }

    /// Drops a cached icon (e.g. after an app update changes its icon).
    func invalidate(bundleId: String) {
        cache.removeObject(forKey: bundleId as NSString)
    }

    /// Clears the whole cache.
    func removeAll() {
        cache.removeAllObjects()
    }
}
