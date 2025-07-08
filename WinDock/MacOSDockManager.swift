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
    
    private let hideDockCommands = [
        "defaults write com.apple.dock autohide -bool true",
        "defaults write com.apple.dock autohide-delay -float 1000",
        "killall Dock"
    ]
    
    private let showDockCommands = [
        "defaults write com.apple.dock autohide -bool false",
        "defaults delete com.apple.dock autohide-delay",
        "killall Dock"
    ]
    
    init() {
        checkDockStatus()
    }
    
    func hideMacOSDock() {
        isProcessing = true
        lastError = nil
        
        let success = executeShellCommands(hideDockCommands)
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
        
        let success = executeShellCommands(showDockCommands)
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
    private func executeShellCommands(_ commands: [String]) -> Bool {
        for command in commands {
            let process = Process()
            process.launchPath = "/bin/bash"
            process.arguments = ["-c", command]
            
            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus != 0 {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    DispatchQueue.main.async {
                        self.lastError = "Command failed: \(command)\nError: \(errorMessage)"
                    }
                    print("Command failed: \(command) with error: \(errorMessage)")
                    return false
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastError = "Failed to execute command: \(command)\nError: \(error.localizedDescription)"
                }
                print("Failed to execute command: \(command) with error: \(error)")
                return false
            }
        }
        return true
    }
    
    private func checkDockStatus() {
        let process = Process()
        process.launchPath = "/usr/bin/defaults"
        process.arguments = ["read", "com.apple.dock", "autohide"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
                
                DispatchQueue.main.async {
                    self.isDockHidden = (output == "1")
                }
            } else {
                // If defaults read fails, assume dock is not hidden
                DispatchQueue.main.async {
                    self.isDockHidden = false
                }
            }
        } catch {
            print("Failed to check dock status: \(error)")
            DispatchQueue.main.async {
                self.isDockHidden = false
            }
        }
    }
}
