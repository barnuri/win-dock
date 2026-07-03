import XCTest
@testable import WinDock

final class WindowEnumerationServiceTests: XCTestCase {

    func testTTLIsShortDuringChurn() {
        XCTAssertEqual(WindowEnumerationService.cacheTTL(secondsSinceLastInvalidation: 0), 1.0)
        XCTAssertEqual(WindowEnumerationService.cacheTTL(secondsSinceLastInvalidation: 9.9), 1.0)
    }

    func testTTLWidensWhenQuiet() {
        XCTAssertEqual(WindowEnumerationService.cacheTTL(secondsSinceLastInvalidation: 10.0), 5.0)
        XCTAssertEqual(WindowEnumerationService.cacheTTL(secondsSinceLastInvalidation: 3600), 5.0)
    }

    func testCachedWindowsValidityRespectsTTL() {
        let fresh = WindowEnumerationService.CachedWindows(windows: [], timestamp: Date())
        let stale = WindowEnumerationService.CachedWindows(windows: [], timestamp: Date().addingTimeInterval(-2))

        XCTAssertTrue(fresh.isValid(ttl: 1.0))
        XCTAssertFalse(stale.isValid(ttl: 1.0))
        XCTAssertTrue(stale.isValid(ttl: 5.0))
    }
}
