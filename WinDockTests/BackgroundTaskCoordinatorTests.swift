import XCTest
@testable import WinDock

@MainActor
final class BackgroundTaskCoordinatorTests: XCTestCase {

    func testUserInitiatedPriorityBypassesDebounce() {
        let coordinator = BackgroundTaskCoordinator(isOnBattery: { false })

        let delay = coordinator.schedulingDelay(for: .userInitiated, now: Date())

        XCTAssertLessThanOrEqual(delay, 0.05, "User-initiated updates must be near-immediate")
    }

    func testBackgroundPriorityUsesBaseDelayWhenIdle() {
        let coordinator = BackgroundTaskCoordinator(isOnBattery: { false })

        let delay = coordinator.schedulingDelay(for: .background, now: Date())

        XCTAssertEqual(delay, 0.1, accuracy: 0.001)
    }

    func testBatteryDoublesBackgroundDelay() {
        let onAC = BackgroundTaskCoordinator(isOnBattery: { false })
        let onBattery = BackgroundTaskCoordinator(isOnBattery: { true })

        let acDelay = onAC.schedulingDelay(for: .background, now: Date())
        let batteryDelay = onBattery.schedulingDelay(for: .background, now: Date())

        XCTAssertEqual(batteryDelay, acDelay * 2.0, accuracy: 0.001)
    }

    func testBatteryDoesNotSlowUserInitiatedLane() {
        let onBattery = BackgroundTaskCoordinator(isOnBattery: { true })

        let delay = onBattery.schedulingDelay(for: .userInitiated, now: Date())

        XCTAssertLessThanOrEqual(delay, 0.05, "Express lane must ignore power source")
    }

    func testBatchLimitForcesFastUpdate() {
        let coordinator = BackgroundTaskCoordinator(isOnBattery: { false })
        coordinator.scheduleUpdate(reason: "one")
        coordinator.scheduleUpdate(reason: "two")
        coordinator.scheduleUpdate(reason: "three")

        let delay = coordinator.schedulingDelay(for: .background, now: Date())

        XCTAssertEqual(delay, 0.05, accuracy: 0.001, "Reaching the batch limit forces a fast flush")
        coordinator.cancelPendingUpdates()
    }
}
