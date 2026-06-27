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
        runDockCommands(hideDockCommands)
    }

    func showMacOSDock() {
        runDockCommands(showDockCommands)
    }

    // Spawns the shell commands (including `killall Dock`) off the main thread so the UI never
    // freezes while the system Dock restarts, then reports status back on the main thread.
    private func runDockCommands(_ commands: [String]) {
        isProcessing = true
        lastError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let success = self.executeShellCommands(commands)
            DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 0.5 : 0.0)) {
                if success {
                    self.checkDockStatus()
                }
                self.isProcessing = false
            }
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
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.launchPath = "/usr/bin/defaults"
            process.arguments = ["read", "com.apple.dock", "autohide"]

            let pipe = Pipe()
            process.standardOutput = pipe

            var hidden = false
            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
                    hidden = (output == "1")
                }
            } catch {
                print("Failed to check dock status: \(error)")
            }

            DispatchQueue.main.async {
                self.isDockHidden = hidden
            }
        }
    }
}
