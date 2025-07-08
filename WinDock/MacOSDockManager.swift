//
//  MacOSDockManager.swift
//  WinDock
//
//  Created by GitHub Copilot on 08/07/2025.
//

import Foundation
import AppKit

class MacOSDockManager: ObservableObject {
    @Published var isDockHidden: Bool = false
    @Published var lastError: String?
    @Published var isProcessing: Bool = false
    
    private let hideDockScript = """
        tell application "System Events"
            tell dock preferences
                set autohide to true
                set autohide delay to 1000
            end tell
        end tell
    """
    
    private let showDockScript = """
        tell application "System Events"
            tell dock preferences
                set autohide to false
            end tell
        end tell
    """
    
    init() {
        checkDockStatus()
    }
    
    func hideMacOSDock() {
        isProcessing = true
        lastError = nil
        
        let success = executeAppleScript(hideDockScript)
        if success {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.checkDockStatus()
                self.isProcessing = false
            }
        } else {
            isProcessing = false
        }
    }
    
    func showMacOSDock() {
        isProcessing = true
        lastError = nil
        
        let success = executeAppleScript(showDockScript)
        if success {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.checkDockStatus()
                self.isProcessing = false
            }
        } else {
            isProcessing = false
        }
    }
    
    @discardableResult
    private func executeAppleScript(_ script: String) -> Bool {
        guard let appleScript = NSAppleScript(source: script) else {
            DispatchQueue.main.async {
                self.lastError = "Failed to create AppleScript"
            }
            return false
        }
        
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        
        if let error = error {
            let errorMessage = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
            DispatchQueue.main.async {
                self.lastError = "AppleScript error: \(errorMessage)"
            }
            print("AppleScript error: \(error)")
            return false
        } else {
            print("AppleScript executed successfully: \(result.stringValue ?? "No result")")
            return true
        }
    }
    
    private func checkDockStatus() {
        let checkScript = """
            tell application "System Events"
                tell dock preferences
                    return autohide
                end tell
            end tell
        """
        
        guard let appleScript = NSAppleScript(source: checkScript) else {
            return
        }
        
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        
        if error == nil {
            DispatchQueue.main.async {
                self.isDockHidden = result.booleanValue
            }
        }
    }
}
