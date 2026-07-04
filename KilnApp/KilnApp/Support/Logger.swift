import Foundation
import OSLog

@MainActor
final class Logger {
    static let shared = Logger()
    private let subsystem = "com.kiln.app"
    private let log: OSLog
    
    private init() {
        self.log = OSLog(subsystem: subsystem, category: "KilnController")
    }
    
    func debug(_ message: String) {
        os_log("%{public}@", log: log, type: .debug, message)
        writeToFile(message)
    }
    
    func info(_ message: String) {
        os_log("%{public}@", log: log, type: .info, message)
        writeToFile(message)
    }
    
    func error(_ message: String) {
        os_log("%{public}@", log: log, type: .error, message)
        writeToFile(message)
    }
    
    private func writeToFile(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"
        
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = url.appendingPathComponent("kiln.log")
        
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}