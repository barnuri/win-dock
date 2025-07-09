import Foundation

final class AppLogger {
    var logsDirectory: URL {
        return logFileURL.deletingLastPathComponent()
    }
    static let shared = AppLogger()
    private let logFileURL: URL
    private let errorFileURL: URL
    private let logQueue = DispatchQueue(label: "AppLoggerQueue", qos: .background)

    private init() {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!.appendingPathComponent("Logs/WinDock", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true, attributes: nil)
        logFileURL = logsDir.appendingPathComponent("app.log")
        errorFileURL = logsDir.appendingPathComponent("errors.log")
    }


    func info(_ message: String) {
        write(message, to: logFileURL)
    }

    func warn(_ message: String) {
        write("[WARNING] " + message, to: logFileURL)
        write(message, to: errorFileURL)
    }

    func error(_ message: String) {
        write("[ERROR] " + message, to: logFileURL)
        write(message, to: errorFileURL)
    }

    private func write(_ message: String, to fileURL: URL) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        logQueue.async {
            if let data = line.data(using: .utf8) {
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
}
