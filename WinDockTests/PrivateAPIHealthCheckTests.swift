import XCTest
@testable import WinDock

final class PrivateAPIHealthCheckTests: XCTestCase {

    func testAllRequiredPrivateSymbolsExistOnThisMacOS() {
        let report = PrivateAPIHealthCheck.shared.run()

        XCTAssertTrue(report.allHealthy, "Missing private symbols: \(report.missingSymbols)")
    }
}
