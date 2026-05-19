import AppKit
import AVFoundation

final class SoundPlayer {
    private let defaults: UserDefaults
    private let playCueNamed: (String) -> Void
    private let playSystemSoundNamed: (String) -> Void
    private let hasInjectedCuePlayer: Bool
    private let hasInjectedSystemSoundPlayer: Bool
    private var players: [AVAudioPlayer] = []

    init(
        defaults: UserDefaults = .standard,
        playCueNamed: ((String) -> Void)? = nil,
        playSystemSoundNamed: ((String) -> Void)? = nil
    ) {
        self.defaults = defaults
        if let playCueNamed {
            self.playCueNamed = playCueNamed
            self.hasInjectedCuePlayer = true
        } else {
            self.playCueNamed = { _ in }
            self.hasInjectedCuePlayer = false
        }
        if let playSystemSoundNamed {
            self.playSystemSoundNamed = playSystemSoundNamed
            self.hasInjectedSystemSoundPlayer = true
        } else {
            self.playSystemSoundNamed = { _ in }
            self.hasInjectedSystemSoundPlayer = false
        }
    }

    func playStartSound() {
        playSound(named: "recordingStart")
    }

    func playStopSound() {
        guard soundEffectsEnabled else { return }
        playSystemSound(named: "Pop")
    }

    private func playSound(named name: String) {
        guard soundEffectsEnabled else { return }
        if hasInjectedCuePlayer {
            playCueNamed(name)
        } else {
            playRecordingStartCue()
        }
    }

    private var soundEffectsEnabled: Bool {
        if defaults.object(forKey: "soundEffectsEnabled") == nil {
            return true
        }
        return defaults.bool(forKey: "soundEffectsEnabled")
    }

    private func playRecordingStartCue() {
        do {
            let data = Self.makeToneWavData(
                frequencies: [880, 1320],
                duration: 0.18,
                sampleRate: 44_100,
                amplitude: 0.85
            )
            let player = try AVAudioPlayer(data: data)
            player.volume = 1.0
            player.prepareToPlay()
            players.append(player)
            DiagnosticLog.write("SoundPlayer: playing recordingStart app cue")
            player.play()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                players.removeAll { !$0.isPlaying }
            }
        } catch {
            DiagnosticLog.write("SoundPlayer: recordingStart app cue failed \(error)")
        }
    }

    private func playSystemSound(named name: String) {
        if hasInjectedSystemSoundPlayer {
            playSystemSoundNamed(name)
            return
        }
        guard let sound = NSSound(named: name) else {
            DiagnosticLog.write("SoundPlayer: missing system sound \(name)")
            return
        }
        sound.volume = 1.0
        sound.play()
    }

    private static func makeToneWavData(
        frequencies: [Double],
        duration: Double,
        sampleRate: Int,
        amplitude: Double
    ) -> Data {
        let channelCount = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channelCount * bitsPerSample / 8
        let blockAlign = channelCount * bitsPerSample / 8
        let frameCount = Int(duration * Double(sampleRate))
        let dataByteCount = frameCount * blockAlign

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(UInt32(36 + dataByteCount).littleEndianData)
        data.append(contentsOf: "WAVEfmt ".utf8)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt16(channelCount).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(byteRate).littleEndianData)
        data.append(UInt16(blockAlign).littleEndianData)
        data.append(UInt16(bitsPerSample).littleEndianData)
        data.append(contentsOf: "data".utf8)
        data.append(UInt32(dataByteCount).littleEndianData)

        let half = max(1, frameCount / max(1, frequencies.count))
        for index in 0..<frameCount {
            let frequency = frequencies[min(index / half, frequencies.count - 1)]
            let t = Double(index) / Double(sampleRate)
            let fadeIn = min(1, Double(index) / 600)
            let fadeOut = min(1, Double(frameCount - index) / 1_200)
            let envelope = fadeIn * fadeOut
            let sample = sin(2 * .pi * frequency * t) * amplitude * envelope
            data.append(Int16(sample * Double(Int16.max)).littleEndianData)
        }
        return data
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
