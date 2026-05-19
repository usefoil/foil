import Foundation

@MainActor
final class RecordingStartCueScheduler {
    private let delayNanoseconds: UInt64
    private let isRecording: () -> Bool
    private let playStartSound: () -> Void

    init(
        delayNanoseconds: UInt64 = 120_000_000,
        isRecording: @escaping () -> Bool,
        playStartSound: @escaping () -> Void
    ) {
        self.delayNanoseconds = delayNanoseconds
        self.isRecording = isRecording
        self.playStartSound = playStartSound
    }

    func schedule() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard isRecording() else { return }
            playStartSound()
        }
    }
}
