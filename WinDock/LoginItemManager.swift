import Foundation
import ServiceManagement
import AppKit

class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()
    
    private let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.windock.app"
    
    private init() {}
    
    var isLoginItemEnabled: Bool {
        get {
            return getLoginItemStatus()
        }
        set {
            setLoginItemStatus(enabled: newValue)
        }
    }
    
    private func getLoginItemStatus() -> Bool {
        // For macOS 13+ we should use modern API, but for compatibility use SMLoginItemSetEnabled
        
        // Check if the app is in login items using Launch Services
        guard let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems, nil)?.takeRetainedValue() else {
            return false
        }
        
        guard let loginItemsArray = LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue() as? [LSSharedFileListItem] else {
            return false
        }
        
        let appURL = Bundle.main.bundleURL
        
        for item in loginItemsArray {
            var resolvedURL: Unmanaged<CFURL>?
            let result = LSSharedFileListItemResolve(item, 0, &resolvedURL, nil)
            
            if result == noErr, let url = resolvedURL?.takeRetainedValue() {
                if (url as URL) == appURL {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func setLoginItemStatus(enabled: Bool) {
        if enabled {
            addToLoginItems()
        } else {
            removeFromLoginItems()
        }
    }
    
    private func addToLoginItems() {
        guard let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems, nil)?.takeRetainedValue() else {
            AppLogger.shared.error("Failed to create login items list")
            return
        }
        
        let appURL = Bundle.main.bundleURL
        
        // Check if already in login items
        if !getLoginItemStatus() {
            let result = LSSharedFileListInsertItemURL(
                loginItems,
                kLSSharedFileListItemBeforeFirst,
                nil,
                nil,
                appURL as CFURL,
                nil,
                nil
            )
            
            if result != nil {
                AppLogger.shared.info("Successfully added WinDock to login items")
            } else {
                AppLogger.shared.error("Failed to add WinDock to login items")
            }
        }
    }
    
    private func removeFromLoginItems() {
        guard let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems, nil)?.takeRetainedValue() else {
            AppLogger.shared.error("Failed to create login items list")
            return
        }
        
        guard let loginItemsArray = LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue() as? [LSSharedFileListItem] else {
            return
        }
        
        let appURL = Bundle.main.bundleURL
        
        for item in loginItemsArray {
            var resolvedURL: Unmanaged<CFURL>?
            let result = LSSharedFileListItemResolve(item, 0, &resolvedURL, nil)
            
            if result == noErr, let url = resolvedURL?.takeRetainedValue() {
                if (url as URL) == appURL {
                    LSSharedFileListItemRemove(loginItems, item)
                    AppLogger.shared.info("Successfully removed WinDock from login items")
                    return
                }
            }
        }
    }
    
    func toggleLoginItem() {
        isLoginItemEnabled.toggle()
    }
}