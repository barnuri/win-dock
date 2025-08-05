import Foundation
import SwiftUI

struct AppSettings: Codable {
    var dockPosition: String = "bottom"
    var dockSize: String = "large"
    var autoHide: Bool = false
    var showOnAllSpaces: Bool = true
    var centerTaskbarIcons: Bool = true
    var showSystemTray: Bool = true
    var showTaskView: Bool = true
    var combineTaskbarButtons: Bool = true
    var useSmallTaskbarButtons: Bool = false
    var taskbarTransparency: Double = 0.95
    var showLabels: Bool = false
    var animationSpeed: Double = 1.0
    var use24HourClock: Bool = true
    var dateFormat: String = "dd/MM/yyyy"
    var searchAppChoice: String = "spotlight"
    var defaultBrowser: String = "com.apple.Safari"
    var defaultTerminal: String = "com.apple.Terminal"
    var logLevel: String = "info"
    var notificationPositionEnabled: Bool = false
    var notificationPosition: String = "topRight"
    
    // Additional settings can be added here
    var exportDate: Date = Date()
    var version: String = "1.0"
}

class SettingsManager: ObservableObject {
    @Published var exportStatus: String?
    @Published var importStatus: String?
    @Published var isProcessing: Bool = false
    
    private let userDefaults = UserDefaults.standard
    
    func exportSettings() -> AppSettings {
        return AppSettings(
            dockPosition: userDefaults.string(forKey: "dockPosition") ?? "bottom",
            dockSize: userDefaults.string(forKey: "dockSize") ?? "large",
            autoHide: userDefaults.bool(forKey: "autoHide"),
            showOnAllSpaces: userDefaults.bool(forKey: "showOnAllSpaces"),
            centerTaskbarIcons: userDefaults.bool(forKey: "centerTaskbarIcons"),
            showSystemTray: userDefaults.bool(forKey: "showSystemTray"),
            showTaskView: userDefaults.bool(forKey: "showTaskView"),
            combineTaskbarButtons: userDefaults.bool(forKey: "combineTaskbarButtons"),
            useSmallTaskbarButtons: userDefaults.bool(forKey: "useSmallTaskbarButtons"),
            taskbarTransparency: userDefaults.double(forKey: "taskbarTransparency") != 0 ? userDefaults.double(forKey: "taskbarTransparency") : 0.95,
            showLabels: userDefaults.bool(forKey: "showLabels"),
            animationSpeed: userDefaults.double(forKey: "animationSpeed") != 0 ? userDefaults.double(forKey: "animationSpeed") : 1.0,
            use24HourClock: userDefaults.bool(forKey: "use24HourClock"),
            dateFormat: userDefaults.string(forKey: "dateFormat") ?? "dd/MM/yyyy",
            searchAppChoice: userDefaults.string(forKey: "searchAppChoice") ?? "spotlight",
            defaultBrowser: userDefaults.string(forKey: "defaultBrowser") ?? "com.apple.Safari",
            defaultTerminal: userDefaults.string(forKey: "defaultTerminal") ?? "com.apple.Terminal",
            logLevel: userDefaults.string(forKey: "logLevel") ?? "info",
            notificationPositionEnabled: userDefaults.bool(forKey: "notificationPositionEnabled"),
            notificationPosition: userDefaults.string(forKey: "notificationPosition") ?? "topRight",
            exportDate: Date(),
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        )
    }
    
    func exportSettingsToFile() {
        isProcessing = true
        exportStatus = nil
        
        let settings = exportSettings()
        
        do {
            let jsonData = try JSONEncoder().encode(settings)
            
            // Create a save panel
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.json]
            savePanel.nameFieldStringValue = "WinDock-Settings-\(dateForFilename()).json"
            savePanel.title = "Export WinDock Settings"
            savePanel.message = "Choose where to save your WinDock settings"
            
            savePanel.begin { [weak self] result in
                DispatchQueue.main.async {
                    if result == .OK, let url = savePanel.url {
                        do {
                            try jsonData.write(to: url)
                            self?.exportStatus = "Settings exported successfully to \(url.lastPathComponent)"
                            AppLogger.shared.info("Settings exported to: \(url.path)")
                        } catch {
                            self?.exportStatus = "Failed to export settings: \(error.localizedDescription)"
                            AppLogger.shared.error("Export failed: \(error)")
                        }
                    } else {
                        self?.exportStatus = "Export cancelled"
                    }
                    self?.isProcessing = false
                }
            }
        } catch {
            exportStatus = "Failed to encode settings: \(error.localizedDescription)"
            AppLogger.shared.error("Encoding failed: \(error)")
            isProcessing = false
        }
    }
    
    func importSettingsFromFile() {
        isProcessing = true
        importStatus = nil
        
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Import WinDock Settings"
        openPanel.message = "Choose a WinDock settings file to import"
        
        openPanel.begin { [weak self] result in
            DispatchQueue.main.async {
                if result == .OK, let url = openPanel.url {
                    self?.importSettings(from: url)
                } else {
                    self?.importStatus = "Import cancelled"
                    self?.isProcessing = false
                }
            }
        }
    }
    
    private func importSettings(from url: URL) {
        do {
            let jsonData = try Data(contentsOf: url)
            let settings = try JSONDecoder().decode(AppSettings.self, from: jsonData)
            
            // Apply settings to UserDefaults
            userDefaults.set(settings.dockPosition, forKey: "dockPosition")
            userDefaults.set(settings.dockSize, forKey: "dockSize")
            userDefaults.set(settings.autoHide, forKey: "autoHide")
            userDefaults.set(settings.showOnAllSpaces, forKey: "showOnAllSpaces")
            userDefaults.set(settings.centerTaskbarIcons, forKey: "centerTaskbarIcons")
            userDefaults.set(settings.showSystemTray, forKey: "showSystemTray")
            userDefaults.set(settings.showTaskView, forKey: "showTaskView")
            userDefaults.set(settings.combineTaskbarButtons, forKey: "combineTaskbarButtons")
            userDefaults.set(settings.useSmallTaskbarButtons, forKey: "useSmallTaskbarButtons")
            userDefaults.set(settings.taskbarTransparency, forKey: "taskbarTransparency")
            userDefaults.set(settings.showLabels, forKey: "showLabels")
            userDefaults.set(settings.animationSpeed, forKey: "animationSpeed")
            userDefaults.set(settings.use24HourClock, forKey: "use24HourClock")
            userDefaults.set(settings.dateFormat, forKey: "dateFormat")
            userDefaults.set(settings.searchAppChoice, forKey: "searchAppChoice")
            userDefaults.set(settings.defaultBrowser, forKey: "defaultBrowser")
            userDefaults.set(settings.defaultTerminal, forKey: "defaultTerminal")
            userDefaults.set(settings.logLevel, forKey: "logLevel")
            userDefaults.set(settings.notificationPositionEnabled, forKey: "notificationPositionEnabled")
            userDefaults.set(settings.notificationPosition, forKey: "notificationPosition")
            
            // Synchronize UserDefaults
            userDefaults.synchronize()
            
            importStatus = "Settings imported successfully from \(url.lastPathComponent)"
            AppLogger.shared.info("Settings imported from: \(url.path)")
            
            
        } catch {
            importStatus = "Failed to import settings: \(error.localizedDescription)"
            AppLogger.shared.error("Import failed: \(error)")
        }
        
        isProcessing = false
    }
    
    func resetToDefaults() {
        isProcessing = true
        
        // Remove all WinDock-related UserDefaults
        let keys = [
            "dockPosition", "dockSize", "autoHide", "showOnAllSpaces", "centerTaskbarIcons",
            "showSystemTray", "showTaskView", "combineTaskbarButtons", "useSmallTaskbarButtons",
            "taskbarTransparency", "showLabels", "animationSpeed", "use24HourClock", "dateFormat",
            "searchAppChoice", "defaultBrowser", "defaultTerminal", "logLevel",
            "notificationPositionEnabled", "notificationPosition"
        ]
        
        for key in keys {
            userDefaults.removeObject(forKey: key)
        }
        
        userDefaults.synchronize()
        
        importStatus = "Settings reset to defaults"
        AppLogger.shared.info("Settings reset to defaults")
        
        
        isProcessing = false
    }
    
    private func dateForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }
    
    func clearStatus() {
        exportStatus = nil
        importStatus = nil
    }
}
