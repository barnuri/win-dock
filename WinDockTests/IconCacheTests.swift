import XCTest
import AppKit
@testable import WinDock

final class IconCacheTests: XCTestCase {

    override func setUp() {
        super.setUp()
        IconCache.shared.removeAll()
    }

    func testIconForBundleIdReturnsSameInstanceOnSecondLookup() {
        let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

        let first = IconCache.shared.icon(forBundleId: "com.apple.finder", appURL: finderURL)
        let second = IconCache.shared.icon(forBundleId: "com.apple.finder", appURL: finderURL)

        XCTAssertTrue(first === second, "Second lookup must be served from cache")
    }

    func testInvalidateDropsCachedIcon() {
        let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

        let first = IconCache.shared.icon(forBundleId: "com.apple.finder", appURL: finderURL)
        IconCache.shared.invalidate(bundleId: "com.apple.finder")
        let second = IconCache.shared.icon(forBundleId: "com.apple.finder", appURL: finderURL)

        XCTAssertFalse(first === second, "Invalidate must force a fresh icon fetch")
    }
}
