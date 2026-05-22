import Foundation

enum DiagnosticLog {
    static func write(_ message: String) {
        guard ProcessInfo.processInfo.environment["GROQTALK_DIAGNOSTICS"] != "0" else { return }
        fputs("[GroqTalkE2E] \(redacted(message))\n", stderr)
    }

    static func redacted(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"gsk_[A-Za-z0-9_\-]+"#,
            with: "<redacted-api-key>",
            options: .regularExpression
        )
    }
}
