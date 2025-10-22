import Foundation
import AppKit
import Combine

/// Centralizes all background task management and debouncing for dock updates.
/// Prevents update storms and ensures smooth UI by intelligently batching notifications.
@MainActor
public class BackgroundTaskCoordinator: ObservableObject {
    @Published public private(set) var isProcessing: Bool = false
    
    private var updateWorkItem: DispatchWorkItem?
    private var lastUpdateTime: Date = .distantPast
    private var coalescedNotifications: Set<String> = []
    
    // Debouncing configuration - tuned for optimal performance
    private let minUpdateInterval: TimeInterval = 0.5  // Increased from 0.2s to prevent storms
    private let baseDelay: TimeInterval = 0.1          // Increased from 0.05s for stability
    private let maxCoalescedUpdates: Int = 3           // Force update after batching 3 notifications
    
    public init() {}
    
    /// Schedules a dock update with intelligent debouncing and batching.
    /// - Parameter reason: Description of why update is needed (for debugging)
    public func scheduleUpdate(reason: String) {
        coalescedNotifications.insert(reason)
        
        // Cancel any pending update
        updateWorkItem?.cancel()
        
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastUpdateTime)
        
        // Calculate adaptive delay based on update frequency and batch size
        let delay: TimeInterval
        if coalescedNotifications.count >= maxCoalescedUpdates {
            // Force immediate update for batched notifications
            delay = 0.05
            AppLogger.shared.debug("Forcing immediate update - batch limit reached (\(coalescedNotifications.count) notifications)")
        } else if timeSinceLastUpdate < minUpdateInterval {
            // Recent update - add extra delay to prevent storms
            delay = (minUpdateInterval - timeSinceLastUpdate) + baseDelay
            AppLogger.shared.debug("Recent update detected - adding delay: \(delay)s")
        } else {
            // Normal case - use base delay
            delay = baseDelay
        }
        
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                await self?.executeUpdate()
            }
        }
        updateWorkItem = workItem
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        AppLogger.shared.debug("Scheduled update with delay: \(delay)s, reason: \(reason)")
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
