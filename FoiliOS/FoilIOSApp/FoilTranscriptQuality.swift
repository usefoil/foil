import Foundation

enum FoilTranscriptQuality {
    static func isAcceptable(_ transcript: String) -> Bool {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        return trimmed.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }
}
