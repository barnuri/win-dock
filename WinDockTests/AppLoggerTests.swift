import XCTest
@testable import WinDock

final class AppLoggerTests: XCTestCase {
    func testBackupsToPruneKeepsNewestBackupsOfTheSameLog() {
        let files = ["app.log", "app.1.log", "app.3.log", "app.2.log", "app.4.log", "errors.1.log", "app.x.log"]

        let pruned = AppLogger.backupsToPrune(fileNames: files, baseName: "app", keep: 3)

        XCTAssertEqual(pruned, ["app.1.log"])
    }

    func testBackupsToPruneReturnsNothingWithinLimit() {
        let pruned = AppLogger.backupsToPrune(fileNames: ["errors.log", "errors.10.log"], baseName: "errors", keep: 3)

        XCTAssertEqual(pruned, [])
    }
}
