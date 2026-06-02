import AppKit

enum RecordingSoundCue: String, CaseIterable, Identifiable {
    case none
    case basso
    case blow
    case bottle
    case frog
    case funk
    case glass
    case hero
    case morse
    case ping
    case pop
    case purr
    case sosumi
    case submarine
    case tink

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .basso:
            return "Basso"
        case .blow:
            return "Blow"
        case .bottle:
            return "Bottle"
        case .frog:
            return "Frog"
        case .funk:
            return "Funk"
        case .glass:
            return "Glass"
        case .hero:
            return "Hero"
        case .morse:
            return "Morse"
        case .ping:
            return "Ping"
        case .pop:
            return "Pop"
        case .purr:
            return "Purr"
        case .sosumi:
            return "Sosumi"
        case .submarine:
            return "Submarine"
        case .tink:
            return "Tink"
        }
    }

    var systemSoundName: String? {
        switch self {
        case .none:
            return nil
        default:
            return displayName
        }
    }

    static let defaultStart: RecordingSoundCue = .bottle
    static let defaultEnd: RecordingSoundCue = .pop
}

final class SoundPlayer {
    private let defaults: UserDefaults
    private let playSystemSoundNamed: (String) -> Void
    private let hasInjectedSystemSoundPlayer: Bool

    init(
        defaults: UserDefaults = .standard,
        playSystemSoundNamed: ((String) -> Void)? = nil
    ) {
        self.defaults = defaults
        if let playSystemSoundNamed {
            self.playSystemSoundNamed = playSystemSoundNamed
            self.hasInjectedSystemSoundPlayer = true
        } else {
            self.playSystemSoundNamed = { _ in }
            self.hasInjectedSystemSoundPlayer = false
        }
    }

    @discardableResult
    func playStartSound() -> Bool {
        play(cue: selectedCue(forKey: Self.startCueKey, defaultCue: .defaultStart))
    }

    @discardableResult
    func playStopSound() -> Bool {
        play(cue: selectedCue(forKey: Self.endCueKey, defaultCue: .defaultEnd))
    }

    func preview(_ cue: RecordingSoundCue) {
        _ = play(cue: cue)
    }

    private func play(cue: RecordingSoundCue) -> Bool {
        guard soundEffectsEnabled else { return false }
        guard let systemSoundName = cue.systemSoundName else {
            return false
        }
        return playSystemSound(named: systemSoundName)
    }

    private var soundEffectsEnabled: Bool {
        if defaults.object(forKey: "soundEffectsEnabled") == nil {
            return true
        }
        return defaults.bool(forKey: "soundEffectsEnabled")
    }

    private func selectedCue(forKey key: String, defaultCue: RecordingSoundCue) -> RecordingSoundCue {
        RecordingSoundCue(rawValue: defaults.string(forKey: key) ?? "") ?? defaultCue
    }

    private func playSystemSound(named name: String) -> Bool {
        if hasInjectedSystemSoundPlayer {
            playSystemSoundNamed(name)
            return true
        }
        guard let sound = NSSound(named: name) else {
            DiagnosticLog.write("SoundPlayer: missing system sound \(name)")
            return false
        }
        sound.volume = 1.0
        DiagnosticLog.write("SoundPlayer: playing \(name) system cue")
        sound.play()
        return true
    }
}

private extension SoundPlayer {
    static let startCueKey = "recordingStartSoundCue"
    static let endCueKey = "recordingEndSoundCue"
}
