import Foundation
import AppKit

final class AppLogger {
    // Enum to represent log levels
    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case critical = "CRITICAL"
        
        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            case .critical: return "🔥"
            }
        }
    }
    
    // Static shared instance
    static let shared = AppLogger()
    
    // Log file paths
    var logsDirectory: URL {
        return logFileURL.deletingLastPathComponent()
    }
    private let logFileURL: URL
    private let errorFileURL: URL
    private let debugFileURL: URL
    
    // Thread-safe logging queue
    private let logQueue = DispatchQueue(label: "AppLoggerQueue", qos: .background)
    
    // Log buffer to store recent logs in memory for quick access
    private var recentLogs: [String] = []
    private let maxRecentLogs = 100
    
    // Configuration
    private let enableConsoleLogs = true
    private let maxLogFileSizeBytes = 10 * 1024 * 1024 // 10 MB
    
    private init() {
        // Set up log directory
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/WinDock", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true, attributes: nil)
        
        logFileURL = logsDir.appendingPathComponent("app.log")
        errorFileURL = logsDir.appendingPathComponent("errors.log")
        debugFileURL = logsDir.appendingPathComponent("debug.log")
        
        // Log app startup
        info("==== WinDock Started ====")
        info("App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")")
        info("macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        
        // Rotate logs if needed
        rotateLogsIfNeeded()
    }
    
    // MARK: - Public Logging Methods
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileInfo = extractFileName(from: file)
        let formattedMessage = "\(fileInfo):\(line) - \(function) - \(message)"
        write(formattedMessage, level: .debug, to: debugFileURL, includeConsole: true)
    }
    
    func info(_ message: String) {
        write(message, level: .info, to: logFileURL)
    }
    
    func warning(_ message: String) {
        write(message, level: .warning, to: logFileURL)
        write(message, level: .warning, to: errorFileURL)
    }
    
    func error(_ message: String, error: Error? = nil) {
        var fullMessage = message
        if let error = error {
            fullMessage += " - Error: \(error.localizedDescription)"
        }
        write(fullMessage, level: .error, to: logFileURL)
        write(fullMessage, level: .error, to: errorFileURL)
    }
    
    func critical(_ message: String, error: Error? = nil) {
        var fullMessage = message
        if let error = error {
            fullMessage += " - Error: \(error.localizedDescription)"
            
            // Add stack trace if available
            if let nsError = error as NSError? {
                fullMessage += "\nStack trace: \(nsError.userInfo)"
            }
        }
        write(fullMessage, level: .critical, to: logFileURL)
        write(fullMessage, level: .critical, to: errorFileURL)
        
        // Show notification for critical errors
        showNotificationIfNeeded(message: "Critical Error: \(message)")
    }
    
    // Get recent logs for in-app display
    func getRecentLogs() -> [String] {
        var logs: [String] = []
        logQueue.sync {
            logs = recentLogs
        }
        return logs
    }
    
    // Open logs directory in Finder
    func showLogsInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([logsDirectory])
    }
    
    // MARK: - Private Helper Methods
    
    private func write(_ message: String, level: LogLevel, to fileURL: URL, includeConsole: Bool = false) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let formattedLog = "[\(timestamp)] \(level.emoji) [\(level.rawValue)] \(message)"
        
        // Store in recent logs buffer
        logQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Add to recent logs buffer
            self.recentLogs.append(formattedLog)
            if self.recentLogs.count > self.maxRecentLogs {
                self.recentLogs.removeFirst()
            }
            
            // Print to console if enabled
            if self.enableConsoleLogs || includeConsole {
                print(formattedLog)
            }
            
            // Write to file
            let lineWithNewline = formattedLog + "\n"
            if let data = lineWithNewline.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: fileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: fileURL)
                }
            }
        }
    }
    
    private func extractFileName(from path: String) -> String {
        let components = path.components(separatedBy: "/")
        return components.last ?? path
    }
    
    private func rotateLogsIfNeeded() {
        logQueue.async {
            self.rotateLogIfNeeded(self.logFileURL)
            self.rotateLogIfNeeded(self.errorFileURL)
            self.rotateLogIfNeeded(self.debugFileURL)
        }
    }
    
    private func rotateLogIfNeeded(_ fileURL: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            if let fileSize = attributes[.size] as? UInt64, fileSize > maxLogFileSizeBytes {
                // Create a backup of the current log
                let backupURL = fileURL.deletingPathExtension().appendingPathExtension("\(Date().timeIntervalSince1970).log")
                try fileManager.moveItem(at: fileURL, to: backupURL)
                
                // Create a new empty log file
                try Data().write(to: fileURL)
                
                info("Log rotated: \(fileURL.lastPathComponent) -> \(backupURL.lastPathComponent)")
            }
        } catch {
            print("Error rotating log file: \(error.localizedDescription)")
        }
    }
    
    private func showNotificationIfNeeded(message: String) {
        DispatchQueue.main.async {
            // Use NSSound since it's universally available
            NSSound.beep()
            
            // Log the critical message
            print("CRITICAL: \(message)")
            
            // Try to show alert if we're in an appropriate context
            if let mainWindow = NSApp.mainWindow {
                let alert = NSAlert()
                alert.messageText = "WinDock Critical Error"
                alert.informativeText = message
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.beginSheetModal(for: mainWindow) { _ in }
            }
            
            // Write to system.log as a fallback
            let process = Process()
            process.launchPath = "/usr/bin/logger"
            process.arguments = ["-t", "WinDock", message]
            try? process.run()
        }
    }
}
