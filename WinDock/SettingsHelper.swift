import SwiftUI
import SettingsAccess

// Helper to open settings from AppKit code
class SettingsHelper: ObservableObject {
    static let shared = SettingsHelper()
    
    @Published var shouldOpenSettings = false
    
    private init() {}
    
    func requestOpenSettings() {
        DispatchQueue.main.async {
            self.shouldOpenSettings = true
        }
    }
}

// SwiftUI view that handles the actual settings opening
struct SettingsAccessHelper: View {
    @Environment(\.openSettingsLegacy) private var openSettingsLegacy
    @ObservedObject private var helper = SettingsHelper.shared
    
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(helper.$shouldOpenSettings) { shouldOpen in
                if shouldOpen {
                    do {
                        try openSettingsLegacy()
                        AppLogger.shared.info("Settings opened successfully via SettingsAccess")
                    } catch {
                        AppLogger.shared.error("Failed to open settings via SettingsAccess: \(error)")
                    }
                    helper.shouldOpenSettings = false
                }
            }
    }
}
