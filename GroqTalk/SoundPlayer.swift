import AppKit

final class SoundPlayer {
    func playStartSound() {
        guard UserDefaults.standard.bool(forKey: "soundEffectsEnabled") else { return }
        NSSound(named: "Tink")?.play()
    }

    func playStopSound() {
        guard UserDefaults.standard.bool(forKey: "soundEffectsEnabled") else { return }
        NSSound(named: "Pop")?.play()
    }
}
