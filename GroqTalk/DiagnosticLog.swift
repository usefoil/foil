import Foundation

enum DiagnosticLog {
    private static let logPath = "/tmp/groqtalk-diag.log"
    private static let queue = DispatchQueue(label: "com.groqtalk.diagnostic-log")
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    static func write(_ message: String) {
        guard isEnabled else { return }
        let line = "\(formatter.string(from: Date())) \(message)\n"
        NSLog("[GroqTalk] %@", message)
        guard let data = line.data(using: .utf8) else { return }
        queue.async {
            if FileManager.default.fileExists(atPath: logPath) {
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data)
            }
        }
    }

    private static var isEnabled: Bool {
        #if DEBUG
        return true
        #else
        return ProcessInfo.processInfo.environment["GROQTALK_DIAGNOSTICS"] == "1"
        #endif
    }
}
