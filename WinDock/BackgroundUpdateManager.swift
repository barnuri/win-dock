import Foundation
import SwiftUI
import Combine
import IOKit.ps
import Network

@MainActor
class BackgroundUpdateManager: ObservableObject {
    static let shared = BackgroundUpdateManager()
    
    @Published var currentTime = Date()
    @Published var batteryInfo = BatteryInfo()
    @Published var networkInfo = NetworkInfo()
    
    private var updateTimer: Timer?
    private let batteryTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect() // Battery every 30s
    private let timeTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect() // Time every second
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        startBackgroundUpdates()
    }
    
    func startBackgroundUpdates() {
        AppLogger.shared.info("BackgroundUpdateManager: Starting background updates")
        
        // Update time every second for real-time clock
        timeTimer
            .sink { [weak self] _ in
                self?.currentTime = Date()
            }
            .store(in: &cancellables)
        
        // Update battery every 30 seconds
        batteryTimer
            .sink { [weak self] _ in
                self?.batteryInfo.update()
            }
            .store(in: &cancellables)
        
        // Start network monitoring immediately
        networkInfo.start()
        
        // Initial updates
        currentTime = Date()
        batteryInfo.update()
        
        AppLogger.shared.info("BackgroundUpdateManager: Background updates started successfully")
    }
    
    func stopBackgroundUpdates() {
        AppLogger.shared.info("BackgroundUpdateManager: Stopping background updates")
        
        cancellables.removeAll()
        networkInfo.stop()
        
        AppLogger.shared.info("BackgroundUpdateManager: Background updates stopped")
    }
    
    deinit {
        // No cleanup needed; SwiftUI lifecycle will handle cancellation
    }
}
