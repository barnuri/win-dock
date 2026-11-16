import XCTest
@testable import WinDock

final class FullscreenDetectionManagerTests: XCTestCase {
    private let primaryDisplay = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let secondaryDisplayAbove = CGRect(x: -200, y: -1080, width: 1920, height: 1080)

    func testWindowCoveringPrimaryDisplayMatches() {
        XCTAssertTrue(FullscreenDetectionManager.windowMatchesAnyDisplay(
            primaryDisplay, displayBounds: [primaryDisplay, secondaryDisplayAbove]))
    }

    func testWindowCoveringSecondaryDisplayMatches() {
        XCTAssertTrue(FullscreenDetectionManager.windowMatchesAnyDisplay(
            secondaryDisplayAbove, displayBounds: [primaryDisplay, secondaryDisplayAbove]))
    }

    func testWindowWithinToleranceMatches() {
        let nearlyFull = primaryDisplay.insetBy(dx: 1, dy: 1)

        XCTAssertTrue(FullscreenDetectionManager.windowMatchesAnyDisplay(nearlyFull, displayBounds: [primaryDisplay]))
    }

    func testMaximizedWindowBelowMenuBarDoesNotMatch() {
        let maximized = CGRect(x: 0, y: 33, width: 1512, height: 949)

        XCTAssertFalse(FullscreenDetectionManager.windowMatchesAnyDisplay(maximized, displayBounds: [primaryDisplay]))
    }

    func testNoDisplaysNeverMatches() {
        XCTAssertFalse(FullscreenDetectionManager.windowMatchesAnyDisplay(primaryDisplay, displayBounds: []))
    }
}
