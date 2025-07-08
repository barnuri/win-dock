//
//  AppManager.swift
//  WinDock
//
//  Created by GitHub Copilot on 08/07/2025.
//

import Foundation
import AppKit
import Combine

struct DockApp: Identifiable, Hashable {
    let id = UUID()
    let bundleIdentifier: String
    let name: String
    let icon: NSImage?
    let url: URL?
    var isRunning: Bool
    var isPinned: Bool
    var windowCount: Int
    var runningApplication: NSRunningApplication?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }
    
    static func == (lhs: DockApp, rhs: DockApp) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}

@MainActor
class AppManager: ObservableObject {
    @Published var dockApps: [DockApp] = []
    
    private var appMonitorTimer: Timer?
    private let pinnedAppsKey = "WinDock.PinnedApps"
    private var pinnedBundleIdentifiers: Set<String> = []
    
    // Default pinned applications
    private let defaultPinnedApps = [
        "com.apple.finder",
        "com.apple.Safari",
        "com.apple.mail",
        "com.apple.systempreferences",
        "com.apple.ActivityMonitor"
    ]
    
    init() {
        loadPinnedApps()
        updateDockApps()
    }
    
    func startMonitoring() {
        // Update immediately
        updateDockApps()
        
        // Set up periodic updates
        appMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                self.updateDockApps()
            }
        }
        
        // Listen for app launch/quit notifications
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidLaunch),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidTerminate),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }
    
    func stopMonitoring() {
        appMonitorTimer?.invalidate()
        appMonitorTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    @objc private func appDidLaunch(_ notification: Notification) {
        Task { @MainActor in
            updateDockApps()
        }
    }
    
    @objc private func appDidTerminate(_ notification: Notification) {
        Task { @MainActor in
            updateDockApps()
        }
    }
    
    private func updateDockApps() {
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
        
        var newDockApps: [DockApp] = []
        var processedBundleIds: Set<String> = []
        
        // Add running applications
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier,
                  !processedBundleIds.contains(bundleId) else { continue }
            
            processedBundleIds.insert(bundleId)
            
            let dockApp = DockApp(
                bundleIdentifier: bundleId,
                name: app.localizedName ?? bundleId,
                icon: app.icon,
                url: app.bundleURL,
                isRunning: true,
                isPinned: pinnedBundleIdentifiers.contains(bundleId),
                windowCount: getWindowCount(for: app),
                runningApplication: app
            )
            newDockApps.append(dockApp)
        }
        
        // Add pinned apps that aren't running
        for bundleId in pinnedBundleIdentifiers {
            if !processedBundleIds.contains(bundleId) {
                if let app = createDockAppForBundleId(bundleId) {
                    newDockApps.append(app)
                }
            }
        }
        
        // Sort: pinned apps first, then by name
        newDockApps.sort { lhs, rhs in
            if lhs.isPinned && !rhs.isPinned {
                return true
            } else if !lhs.isPinned && rhs.isPinned {
                return false
            } else {
                return lhs.name < rhs.name
            }
        }
        
        dockApps = newDockApps
    }
    
    private func createDockAppForBundleId(_ bundleId: String) -> DockApp? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
              let bundle = Bundle(url: appURL) else {
            return nil
        }
        
        let name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String ??
                   bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
                   bundle.infoDictionary?["CFBundleName"] as? String ??
                   bundleId
        
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        
        return DockApp(
            bundleIdentifier: bundleId,
            name: name,
            icon: icon,
            url: appURL,
            isRunning: false,
            isPinned: true,
            windowCount: 0,
            runningApplication: nil
        )
    }
    
    private func getWindowCount(for app: NSRunningApplication) -> Int {
        // This is a simplified approach - in a real implementation,
        // you'd use accessibility APIs or window server APIs
        return 1
    }
    
    // MARK: - App Actions
    
    func activateApp(_ app: DockApp) {
        if let runningApp = app.runningApplication {
            if #available(macOS 14.0, *) {
                runningApp.activate()
            } else {
                runningApp.activate(options: [.activateIgnoringOtherApps])
            }
        } else if let appURL = app.url {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        } else {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
                let configuration = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            }
        }
    }
    
    func hideApp(_ app: DockApp) {
        app.runningApplication?.hide()
    }
    
    func quitApp(_ app: DockApp) {
        app.runningApplication?.terminate()
    }
    
    func showAllWindows(for app: DockApp) {
        if let runningApp = app.runningApplication {
            // Unhide the app if it's hidden
            if runningApp.isHidden {
                runningApp.unhide()
            }
            
            // Activate the app and show all windows
            if #available(macOS 14.0, *) {
                runningApp.activate(options: [.activateAllWindows])
            } else {
                runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
            
            // Additional method to ensure all windows are shown
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Use AppleScript as a fallback to show all windows
                let script = """
                tell application "\(app.name)"
                    activate
                    set visible of every window to true
                end tell
                """
                
                if let appleScript = NSAppleScript(source: script) {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                }
            }
        }
    }
    
    func launchApp(_ app: DockApp) {
        activateApp(app)
    }
    
    func pinApp(_ app: DockApp) {
        pinnedBundleIdentifiers.insert(app.bundleIdentifier)
        savePinnedApps()
        updateDockApps()
    }
    
    func unpinApp(_ app: DockApp) {
        pinnedBundleIdentifiers.remove(app.bundleIdentifier)
        savePinnedApps()
        updateDockApps()
    }
    
    // MARK: - Persistence
    
    private func loadPinnedApps() {
        if let saved = UserDefaults.standard.array(forKey: pinnedAppsKey) as? [String] {
            pinnedBundleIdentifiers = Set(saved)
        } else {
            // First launch - use default pinned apps
            pinnedBundleIdentifiers = Set(defaultPinnedApps)
            savePinnedApps()
        }
    }
    
    private func savePinnedApps() {
        UserDefaults.standard.set(Array(pinnedBundleIdentifiers), forKey: pinnedAppsKey)
    }
}
