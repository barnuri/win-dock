import Foundation
import AppKit
import Combine
import IOKit.ps

/// Centralizes all background task management and debouncing for dock updates.
/// Prevents update storms and ensures smooth UI by intelligently batching notifications.
@MainActor
public class BackgroundTaskCoordinator: ObservableObject {
    /// Scheduling lane for a dock update.
    /// `.userInitiated` (clicks, drags) bypasses debouncing for instant feedback;
    /// `.background` (workspace notification churn) keeps the adaptive debounce.
    public enum UpdatePriority {
        case userInitiated
        case background
    }

    @Published public private(set) var isProcessing: Bool = false

    private var updateWorkItem: DispatchWorkItem?
    private var lastUpdateTime: Date = .distantPast
    private var coalescedNotifications: Set<String> = []

    // Debouncing configuration - tuned for optimal performance
    private let minUpdateInterval: TimeInterval = 0.5  // Increased from 0.2s to prevent storms
    private let baseDelay: TimeInterval = 0.1          // Increased from 0.05s for stability
    private let maxCoalescedUpdates: Int = 3           // Force update after batching 3 notifications
    private let expressDelay: TimeInterval = 0.01      // User-initiated lane: near-immediate
    private let batteryDelayMultiplier: Double = 2.0   // Longer debounce on battery to save energy

    private let isOnBattery: () -> Bool

    /// - Parameter isOnBattery: Injectable power-source check (overridable in tests).
    public init(isOnBattery: @escaping () -> Bool = BackgroundTaskCoordinator.systemIsOnBattery) {
        self.isOnBattery = isOnBattery
    }

    /// True when the Mac is running on battery power.
    nonisolated public static func systemIsOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return false
        }
        // "Get" accessor returns a non-owned static constant — must not be retained.
        guard let sourceType = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? else {
            return false
        }
        return sourceType == kIOPSBatteryPowerValue
    }

    /// Schedules a dock update with intelligent debouncing and batching.
    /// - Parameters:
    ///   - reason: Description of why update is needed (for debugging)
    ///   - priority: `.userInitiated` bypasses debouncing; `.background` (default) debounces
    public func scheduleUpdate(reason: String, priority: UpdatePriority = .background) {
        coalescedNotifications.insert(reason)

        // Cancel any pending update
        updateWorkItem?.cancel()

        let delay = schedulingDelay(for: priority, now: Date())

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                await self?.executeUpdate()
            }
        }
        updateWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        AppLogger.shared.debug("Scheduled update with delay: \(delay)s, priority: \(priority), reason: \(reason)")
    }

    /// Computes the delay for a scheduling request. Internal for unit testing.
    func schedulingDelay(for priority: UpdatePriority, now: Date) -> TimeInterval {
        if priority == .userInitiated {
            return expressDelay
        }

        let multiplier = isOnBattery() ? batteryDelayMultiplier : 1.0
        let timeSinceLastUpdate = now.timeIntervalSince(lastUpdateTime)

        if coalescedNotifications.count >= maxCoalescedUpdates {
            AppLogger.shared.debug("Forcing immediate update - batch limit reached (\(coalescedNotifications.count) notifications)")
            return 0.05
        }
        if timeSinceLastUpdate < minUpdateInterval {
            return ((minUpdateInterval - timeSinceLastUpdate) + baseDelay) * multiplier
        }
        return baseDelay * multiplier
    }

    /// Cancels all pending updates.
    public func cancelPendingUpdates() {
        updateWorkItem?.cancel()
        updateWorkItem = nil
        coalescedNotifications.removeAll()
        AppLogger.shared.debug("Cancelled all pending updates")
    }

    private func executeUpdate() async {
        guard !coalescedNotifications.isEmpty else {
            AppLogger.shared.debug("No notifications to process, skipping update")
            return
        }

        isProcessing = true
        let reasons = coalescedNotifications
        coalescedNotifications.removeAll()

        AppLogger.shared.info("Executing dock update for reasons: \(reasons.joined(separator: ", "))")

        // Notify AppManager to perform update
        NotificationCenter.default.post(
            name: NSNotification.Name("PerformDockUpdate"),
            object: nil,
            userInfo: ["reasons": reasons]
        )

        lastUpdateTime = Date()
        isProcessing = false

        AppLogger.shared.debug("Update completed, processing flag cleared")
    }
}
