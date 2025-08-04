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
    
    private var cancellables = Set<AnyCancellable>()
    private let backgroundQueue = DispatchQueue(label: "background.updates", qos: .utility)
    
    private init() {
        startBackgroundUpdates()
    }
    
    func startBackgroundUpdates() {
        AppLogger.shared.info("BackgroundUpdateManager: Starting background updates")
        
        // Use more efficient time updates - only update when second changes
        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newTime in
                guard let self = self else { return }
                // Only update if the second actually changed to prevent unnecessary updates
                if Calendar.current.component(.second, from: self.currentTime) != Calendar.current.component(.second, from: newTime) {
                    self.currentTime = newTime
                }
            }
            .store(in: &cancellables)
        
        // Update battery info on background queue every 30 seconds
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .receive(on: backgroundQueue)
            .sink { [weak self] _ in
                guard let self = self else { return }
                var batteryInfo = BatteryInfo()
                batteryInfo.update()
                
                DispatchQueue.main.async {
                    self.batteryInfo = batteryInfo
                }
            }
            .store(in: &cancellables)
        
        // Start network monitoring immediately on main thread
        networkInfo.start()
        
        // Initial updates
        currentTime = Date()
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            var batteryInfo = BatteryInfo()
            batteryInfo.update()
            
            DispatchQueue.main.async {
                self.batteryInfo = batteryInfo
            }
        }
        
        AppLogger.shared.info("BackgroundUpdateManager: Background updates started successfully")
    }
    
    func stopBackgroundUpdates() {
        AppLogger.shared.info("BackgroundUpdateManager: Stopping background updates")
        
        cancellables.removeAll()
        networkInfo.stop()
        
        AppLogger.shared.info("BackgroundUpdateManager: Background updates stopped")
    }
    
    deinit {
        cancellables.removeAll()
    }
}
