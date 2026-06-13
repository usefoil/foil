import AVFAudio
import CoreAudio
import Foundation

/// Audio format for recording output. Used across AudioRecorder, TranscriptionService,
/// AppState, and MenuBarView to eliminate stringly-typed format routing.
enum AudioFormat: String, CaseIterable, Codable {
    case m4a
    case wav
    case flac

    var filename: String { "audio.\(rawValue)" }

    var contentType: String {
        switch self {
        case .m4a:  "audio/mp4"
        case .wav:  "audio/wav"
        case .flac: "audio/flac"
        }
    }
}

/// Language hint for Whisper transcription. When not `.auto`, the ISO 639-1
/// code is included in the API request to constrain language detection and improve accuracy.
enum Language: String, CaseIterable, Codable {
    case auto
    case en, es, fr, de, pt, it, ja, zh, ko, hi, ar, ru

    var displayName: String {
        switch self {
        case .auto: "Auto-detect"
        case .en:   "English"
        case .es:   "Spanish"
        case .fr:   "French"
        case .de:   "German"
        case .pt:   "Portuguese"
        case .it:   "Italian"
        case .ja:   "Japanese"
        case .zh:   "Chinese"
        case .ko:   "Korean"
        case .hi:   "Hindi"
        case .ar:   "Arabic"
        case .ru:   "Russian"
        }
    }
}

final class AudioRecorder: @unchecked Sendable {
    static let defaultMaxRecordingDuration: TimeInterval = 600
    static let defaultMaxBufferedFrames = Int(targetSampleRate * defaultMaxRecordingDuration)

    private var audioEngine: AVAudioEngine?
    private var buffers: [AVAudioPCMBuffer] = []
    private var conversionErrorCount = 0
    private var capturedFrameCount = 0
    private var didExceedFrameLimit = false
    private let bufferLock = NSLock()
    private let encodingQueue = DispatchQueue(label: "com.neonwatty.foil.audioencoding", qos: .userInitiated)
    private let maxBufferedFrames: Int
    var levelUpdateHandler: ((Float) -> Void)?

    private static let targetSampleRate: Double = 16000
    private static let targetChannels: AVAudioChannelCount = 1

    private static var pcmFormat: AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: false
        )
    }

    init(maxBufferedFrames: Int = AudioRecorder.defaultMaxBufferedFrames) {
        self.maxBufferedFrames = maxBufferedFrames
    }

    func startRecording(deviceID: AudioDeviceID? = nil) throws {
        cancelRecording()

        if deviceID == nil, Self.defaultInputDeviceID() == nil, Self.availableInputDevices().isEmpty {
            DiagnosticLog.write("AudioRecorder: no input devices available")
            throw RecordingError.deviceSelectionFailed
        }

        let engine = AVAudioEngine()
        audioEngine = engine
        resetCapturedState()

        let inputNode = engine.inputNode

        if let deviceID {
            if let audioUnit = inputNode.audioUnit {
                var id = deviceID
                let status = AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &id,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                if status != noErr {
                    DiagnosticLog.write("AudioRecorder: failed to set input device \(deviceID): OSStatus \(status)")
                    throw RecordingError.deviceSelectionFailed
                }
                var readbackID = AudioDeviceID(0)
                var readbackSize = UInt32(MemoryLayout<AudioDeviceID>.size)
                let readbackStatus = AudioUnitGetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &readbackID,
                    &readbackSize
                )
                DiagnosticLog.write(
                    "AudioRecorder: audio unit input device set requested=\(deviceID) readback=\(readbackID) status=\(readbackStatus)"
                )
            } else {
                DiagnosticLog.write("AudioRecorder: input audio unit unavailable while setting device \(deviceID)")
            }
        }

        let hwFormat = inputNode.outputFormat(forBus: 0)
        DiagnosticLog.write(
            "AudioRecorder: input format sampleRate=\(Int(hwFormat.sampleRate)) channels=\(hwFormat.channelCount) selectedDeviceID=\(deviceID.map(String.init) ?? "systemDefault")"
        )
        DiagnosticLog.write(
            "AudioRecorder: recording route \(Self.audioRouteDescription(input: Self.audioRouteDevice(for: deviceID ?? Self.defaultInputDeviceID()), output: Self.audioRouteDevice(for: Self.defaultOutputDeviceID())))"
        )

        guard let targetFormat = Self.pcmFormat else {
            throw RecordingError.audioFormatUnavailable
        }
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            self.levelUpdateHandler?(Self.normalizedRMSLevel(in: buffer))
            let sourceFormat = buffer.format
            guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                self.bufferLock.withLock {
                    self.conversionErrorCount += 1
                }
                DiagnosticLog.write(
                    "audioRecorder: converter unavailable sourceSampleRate=\(Int(sourceFormat.sampleRate)) channels=\(sourceFormat.channelCount)"
                )
                return
            }
            let ratio = Self.targetSampleRate / sourceFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard outputFrameCount > 0,
                  let converted = AVAudioPCMBuffer(
                      pcmFormat: targetFormat, frameCapacity: outputFrameCount
                  ) else { return }

            var error: NSError?
            converter.convert(to: converted, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if let error {
                self.bufferLock.withLock {
                    self.conversionErrorCount += 1
                }
                DiagnosticLog.write("audioRecorder: conversion error \(error.localizedDescription)")
            } else if converted.frameLength > 0 {
                self.appendConvertedBuffer(converted)
            }
        }

        try engine.start()
    }

    /// Stops recording and encodes captured audio in the given format.
    /// Returns nil if no recording was active or no audio was captured (benign short press).
    /// Throws if audio was captured but encoding failed, or if all buffers were lost to conversion errors.
    func stopRecording(format: AudioFormat = .wav) throws -> URL? {
        let capturedAudio = try stopAndCaptureRecording()
        return try encodeCapturedAudio(capturedAudio, format: format)
    }

    /// Stops recording immediately, then encodes captured audio off the caller's actor.
    /// Engine/tap teardown stays synchronous so recording state is finalized before UI updates.
    func stopRecordingAsync(format: AudioFormat = .wav) async throws -> URL? {
        let capturedAudio = try stopAndCaptureRecording()
        return try await withCheckedThrowingContinuation { continuation in
            encodingQueue.async { [self] in
                do {
                    let url = try encodeCapturedAudio(capturedAudio, format: format)
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func stopAndCaptureRecording() throws -> CapturedAudio? {
        guard let engine = audioEngine else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil

        let (captured, errors, exceededLimit) = bufferLock.withLock { () -> ([AVAudioPCMBuffer], Int, Bool) in
            let b = buffers; let e = conversionErrorCount
            let exceeded = didExceedFrameLimit
            buffers = []
            conversionErrorCount = 0
            capturedFrameCount = 0
            didExceedFrameLimit = false
            return (b, e, exceeded)
        }

        if exceededLimit {
            throw RecordingError.recordingTooLong
        }
        if captured.isEmpty && errors > 0 {
            throw RecordingError.conversionFailed(errorCount: errors)
        }
        guard !captured.isEmpty else { return nil }
        return CapturedAudio(buffers: captured, conversionErrorCount: errors)
    }

    private func encodeCapturedAudio(_ capturedAudio: CapturedAudio?, format: AudioFormat) throws -> URL? {
        guard let capturedAudio else { return nil }
        let captured = capturedAudio.buffers
        let errors = capturedAudio.conversionErrorCount
        let frameCount = captured.reduce(0) { $0 + Int($1.frameLength) }
        DiagnosticLog.write(
            "audioRecorder: captured buffers=\(captured.count) frames=\(frameCount) conversionErrors=\(errors) format=\(format.rawValue)"
        )

        let url: URL
        switch format {
        case .m4a:  url = try writeM4A(buffers: captured)
        case .wav:  url = try writeWAV(buffers: captured)
        case .flac: url = try writeFLAC(buffers: captured)
        }
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        DiagnosticLog.write("audioRecorder: wrote file=\(url.lastPathComponent) bytes=\(fileSize)")
        return url
    }

    func cancelRecording() {
        guard let engine = audioEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil
        resetCapturedState()
    }

    private func appendConvertedBuffer(_ buffer: AVAudioPCMBuffer) {
        bufferLock.withLock {
            guard !didExceedFrameLimit else { return }
            let frameLength = Int(buffer.frameLength)
            guard capturedFrameCount + frameLength <= maxBufferedFrames else {
                didExceedFrameLimit = true
                buffers.removeAll()
                capturedFrameCount = 0
                return
            }
            buffers.append(buffer)
            capturedFrameCount += frameLength
        }
    }

    private func resetCapturedState() {
        bufferLock.withLock {
            buffers = []
            conversionErrorCount = 0
            capturedFrameCount = 0
            didExceedFrameLimit = false
        }
    }

    static func normalizedRMSLevel(in buffer: AVAudioPCMBuffer) -> Float {
        guard buffer.frameLength > 0,
              let channelData = buffer.floatChannelData else {
            return 0
        }

        let channelCount = max(1, Int(buffer.format.channelCount))
        let frameCount = Int(buffer.frameLength)
        var sumSquares: Float = 0
        var sampleCount = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameCount {
                let sample = samples[frame]
                sumSquares += sample * sample
            }
            sampleCount += frameCount
        }

        guard sampleCount > 0 else { return 0 }
        let rms = sqrt(sumSquares / Float(sampleCount))
        guard rms.isFinite else { return 0 }
        return min(max(rms / 0.35, 0), 1)
    }

    // MARK: - WAV output

    /// Internal for testing — callers should use stopRecording(format:).
    func writeWAV(buffers: [AVAudioPCMBuffer]) throws -> URL {
        let url = tempURL(extension: "wav")
        // Write as 16-bit PCM WAV (smaller than float32 WAV)
        guard let int16Format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: Self.targetChannels,
            interleaved: true
        ) else {
            throw RecordingError.audioFormatUnavailable
        }
        let file = try AVAudioFile(forWriting: url, settings: int16Format.settings)
        for buffer in buffers {
            try file.write(from: buffer)
        }
        return url
    }

    // MARK: - M4A/AAC output

    /// Internal for testing — callers should use stopRecording(format:).
    func writeM4A(buffers: [AVAudioPCMBuffer]) throws -> URL {
        let url = tempURL(extension: "m4a")
        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Self.targetSampleRate,
            AVNumberOfChannelsKey: Self.targetChannels,
        ]
        let file = try AVAudioFile(forWriting: url, settings: aacSettings)
        for buffer in buffers {
            try file.write(from: buffer)
        }
        return url
    }

    // MARK: - FLAC output

    /// Internal for testing — callers should use stopRecording(format:).
    func writeFLAC(buffers: [AVAudioPCMBuffer]) throws -> URL {
        let url = tempURL(extension: "flac")
        let flacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatFLAC,
            AVSampleRateKey: Self.targetSampleRate,
            AVNumberOfChannelsKey: Self.targetChannels,
        ]
        let file = try AVAudioFile(forWriting: url, settings: flacSettings)
        for buffer in buffers {
            try file.write(from: buffer)
        }
        return url
    }

    private func tempURL(extension ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-\(UUID().uuidString).\(ext)")
    }

    // MARK: - Audio device enumeration

    enum AudioDeviceTransport: String, Equatable, Hashable {
        case unknown
        case builtIn
        case aggregate
        case virtual
        case pci
        case usb
        case fireWire
        case bluetooth
        case bluetoothLE
        case hdmi
        case displayPort
        case airPlay
        case avb
        case thunderbolt
        case continuityCaptureWired
        case continuityCaptureWireless
        case other

        var displayName: String {
            switch self {
            case .unknown: "Unknown"
            case .builtIn: "Built-in"
            case .aggregate: "Aggregate"
            case .virtual: "Virtual"
            case .pci: "PCI"
            case .usb: "USB"
            case .fireWire: "FireWire"
            case .bluetooth: "Bluetooth"
            case .bluetoothLE: "Bluetooth LE"
            case .hdmi: "HDMI"
            case .displayPort: "DisplayPort"
            case .airPlay: "AirPlay"
            case .avb: "AVB"
            case .thunderbolt: "Thunderbolt"
            case .continuityCaptureWired: "Continuity Capture wired"
            case .continuityCaptureWireless: "Continuity Capture wireless"
            case .other: "Other"
            }
        }

        var isBluetooth: Bool {
            self == .bluetooth || self == .bluetoothLE
        }

        static func fromCoreAudioTransportType(_ rawValue: UInt32) -> Self {
            switch rawValue {
            case kAudioDeviceTransportTypeUnknown: .unknown
            case kAudioDeviceTransportTypeBuiltIn: .builtIn
            case kAudioDeviceTransportTypeAggregate: .aggregate
            case kAudioDeviceTransportTypeVirtual: .virtual
            case kAudioDeviceTransportTypePCI: .pci
            case kAudioDeviceTransportTypeUSB: .usb
            case kAudioDeviceTransportTypeFireWire: .fireWire
            case kAudioDeviceTransportTypeBluetooth: .bluetooth
            case kAudioDeviceTransportTypeBluetoothLE: .bluetoothLE
            case kAudioDeviceTransportTypeHDMI: .hdmi
            case kAudioDeviceTransportTypeDisplayPort: .displayPort
            case kAudioDeviceTransportTypeAirPlay: .airPlay
            case kAudioDeviceTransportTypeAVB: .avb
            case kAudioDeviceTransportTypeThunderbolt: .thunderbolt
            case kAudioDeviceTransportTypeContinuityCaptureWired: .continuityCaptureWired
            case kAudioDeviceTransportTypeContinuityCaptureWireless: .continuityCaptureWireless
            default: .other
            }
        }
    }

    struct AudioDevice: Identifiable, Equatable, Hashable {
        let id: AudioDeviceID
        let uid: String
        let name: String
        let isInput: Bool
        let transport: AudioDeviceTransport
    }

    struct AudioRouteDevice: Equatable {
        let id: AudioDeviceID
        let name: String
        let transport: AudioDeviceTransport
        let sampleRate: Double?
    }

    enum InputPreparationReason: String, Equatable {
        case systemDefault
        case explicitSelection
        case explicitSelectionMissing
        case noSystemDefaultFallback
        case avoidBluetoothDefault
        case bluetoothDefaultWithoutFallback
    }

    struct InputPreparationDecision: Equatable {
        let device: AudioDevice?
        let shouldSetDefaultInput: Bool
        let reason: InputPreparationReason
        let defaultDevice: AudioDevice?
        let defaultDeviceID: AudioDeviceID?
    }

    static func availableInputDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }

        var inputDevices: [AudioDevice] = []

        for deviceID in deviceIDs {
            // Check for input channels via stream configuration on the input scope
            var inputScopeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var configSize: UInt32 = 0
            let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &inputScopeAddress, 0, nil, &configSize)
            guard sizeStatus == noErr, configSize > 0 else { continue }

            let bufferListPointer = UnsafeMutableRawPointer.allocate(byteCount: Int(configSize), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { bufferListPointer.deallocate() }

            var configSizeMutable = configSize
            let dataStatus = AudioObjectGetPropertyData(deviceID, &inputScopeAddress, 0, nil, &configSizeMutable, bufferListPointer)
            guard dataStatus == noErr else { continue }

            let totalChannels = bufferListPointer.withMemoryRebound(
                to: AudioBufferList.self,
                capacity: 1
            ) { ptr in
                UnsafeMutableAudioBufferListPointer(ptr)
                    .reduce(0) { $0 + Int($1.mNumberChannels) }
            }
            guard totalChannels > 0 else { continue }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameRef: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let nameStatus = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &nameRef)
            let deviceName = nameStatus == noErr ? (nameRef?.takeRetainedValue() as String? ?? "Unknown Device") : "Unknown Device"

            // Get stable device UID (persists across reboots, unlike AudioDeviceID)
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidRef: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let uidStatus = AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uidRef)
            let deviceUID = uidStatus == noErr ? (uidRef?.takeRetainedValue() as String? ?? "") : ""
            guard !deviceUID.isEmpty else { continue }

            inputDevices.append(AudioDevice(
                id: deviceID,
                uid: deviceUID,
                name: deviceName,
                isInput: true,
                transport: transportType(for: deviceID)
            ))
        }

        return inputDevices
    }

    static func effectiveInputDevice(forUID uid: String?) -> AudioDevice? {
        let devices = availableInputDevices()
        if let uid {
            return devices.first { $0.uid == uid }
        }
        guard let defaultID = defaultInputDeviceID() else {
            return nil
        }
        return devices.first { $0.id == defaultID }
    }

    /// Resolves a stable device UID to the current AudioDeviceID, or nil if not found.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        availableInputDevices().first { $0.uid == uid }?.id
    }

    /// Prepares an explicit input selection for recording.
    ///
    /// Setting the AudioUnit's current device is enough to capture from a selected
    /// mic, but Bluetooth headsets can still enter headset/SCO mode when macOS's
    /// system default input remains on the headset. When the user explicitly
    /// selects an input device, align the system default input just before
    /// recording starts so AirPods can remain output-only with a built-in mic.
    /// When System Default points at a Bluetooth microphone, prefer a non-Bluetooth
    /// mic for recording so playback can stay on the high-quality output route.
    static func prepareInputDeviceForRecording(selectedUID uid: String?) -> AudioDeviceID? {
        let devices = availableInputDevices()
        let defaultBeforeID = defaultInputDeviceID()
        let decision = inputPreparationDecision(
            selectedUID: uid,
            devices: devices,
            defaultInputDeviceID: defaultBeforeID
        )
        DiagnosticLog.write("AudioRecorder: input policy \(inputPolicyDescription(decision))")

        guard let selectedDevice = decision.device else {
            return nil
        }
        guard decision.shouldSetDefaultInput else {
            return selectedDevice.id
        }

        DiagnosticLog.write(
            "AudioRecorder: selected input uid=\(selectedDevice.uid) name=\(selectedDevice.name) id=\(selectedDevice.id) transport=\(selectedDevice.transport.displayName) defaultBefore=\(inputDeviceDescription(decision.defaultDevice, id: decision.defaultDeviceID))"
        )

        let setStatus = setDefaultInputDeviceID(selectedDevice.id)
        let defaultAfterID = defaultInputDeviceID()
        let defaultAfter = defaultAfterID.flatMap { id in availableInputDevices().first { $0.id == id } }
        DiagnosticLog.write(
            "AudioRecorder: set default input requested=\(selectedDevice.id) status=\(setStatus) defaultAfter=\(inputDeviceDescription(defaultAfter, id: defaultAfterID))"
        )

        return selectedDevice.id
    }

    static func inputPreparationDecision(
        selectedUID uid: String?,
        devices: [AudioDevice],
        defaultInputDeviceID: AudioDeviceID?
    ) -> InputPreparationDecision {
        let defaultDevice = defaultInputDeviceID.flatMap { id in devices.first { $0.id == id } }

        if let uid {
            guard let selectedDevice = devices.first(where: { $0.uid == uid }) else {
                return InputPreparationDecision(
                    device: nil,
                    shouldSetDefaultInput: false,
                    reason: .explicitSelectionMissing,
                    defaultDevice: defaultDevice,
                    defaultDeviceID: defaultInputDeviceID
                )
            }
            return InputPreparationDecision(
                device: selectedDevice,
                shouldSetDefaultInput: true,
                reason: .explicitSelection,
                defaultDevice: defaultDevice,
                defaultDeviceID: defaultInputDeviceID
            )
        }

        guard let defaultDevice else {
            guard let fallbackDevice = preferredNonBluetoothInputDevice(from: devices) ?? devices.first else {
                return InputPreparationDecision(
                    device: nil,
                    shouldSetDefaultInput: false,
                    reason: .systemDefault,
                    defaultDevice: nil,
                    defaultDeviceID: defaultInputDeviceID
                )
            }
            return InputPreparationDecision(
                device: fallbackDevice,
                shouldSetDefaultInput: true,
                reason: .noSystemDefaultFallback,
                defaultDevice: nil,
                defaultDeviceID: defaultInputDeviceID
            )
        }

        guard defaultDevice.transport.isBluetooth else {
            return InputPreparationDecision(
                device: nil,
                shouldSetDefaultInput: false,
                reason: .systemDefault,
                defaultDevice: defaultDevice,
                defaultDeviceID: defaultInputDeviceID
            )
        }

        guard let fallbackDevice = preferredNonBluetoothInputDevice(from: devices) else {
            return InputPreparationDecision(
                device: nil,
                shouldSetDefaultInput: false,
                reason: .bluetoothDefaultWithoutFallback,
                defaultDevice: defaultDevice,
                defaultDeviceID: defaultInputDeviceID
            )
        }

        return InputPreparationDecision(
            device: fallbackDevice,
            shouldSetDefaultInput: true,
            reason: .avoidBluetoothDefault,
            defaultDevice: defaultDevice,
            defaultDeviceID: defaultInputDeviceID
        )
    }

    static func audioRouteDescription(input: AudioRouteDevice?, output: AudioRouteDevice?) -> String {
        "input=\(audioRouteDeviceDescription(input)) output=\(audioRouteDeviceDescription(output))"
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private static func setDefaultInputDeviceID(_ deviceID: AudioDeviceID) -> OSStatus {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableDeviceID = deviceID
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        )
    }

    private static func preferredNonBluetoothInputDevice(from devices: [AudioDevice]) -> AudioDevice? {
        devices.first { $0.transport == .builtIn }
            ?? devices.first { $0.transport != .unknown && !$0.transport.isBluetooth }
    }

    private static func inputPolicyDescription(_ decision: InputPreparationDecision) -> String {
        let selectedDescription = inputDeviceDescription(decision.device, id: decision.device?.id)
        let defaultDescription = inputDeviceDescription(decision.defaultDevice, id: decision.defaultDeviceID)
        return "reason=\(decision.reason.rawValue) selected=\(selectedDescription) shouldSetDefaultInput=\(decision.shouldSetDefaultInput) defaultBefore=\(defaultDescription)"
    }

    private static func audioRouteDevice(for id: AudioDeviceID?) -> AudioRouteDevice? {
        guard let id else { return nil }
        return AudioRouteDevice(
            id: id,
            name: audioDeviceName(for: id),
            transport: transportType(for: id),
            sampleRate: nominalSampleRate(for: id)
        )
    }

    private static func audioRouteDeviceDescription(_ device: AudioRouteDevice?) -> String {
        guard let device else { return "none" }
        return "\(device.name)(id=\(device.id), transport=\(device.transport.displayName), sampleRate=\(sampleRateDescription(device.sampleRate)))"
    }

    private static func inputDeviceDescription(_ device: AudioDevice?, id: AudioDeviceID?) -> String {
        if let device {
            return "\(device.name)(id=\(device.id), transport=\(device.transport.displayName))"
        }
        if let id {
            return "unknown(id=\(id))"
        }
        return "none"
    }

    private static func audioDeviceName(for deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameRef: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &nameRef)
        return status == noErr ? (nameRef?.takeRetainedValue() as String? ?? "Unknown Device") : "Unknown Device"
    }

    private static func nominalSampleRate(for deviceID: AudioDeviceID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate = Float64(0)
        var dataSize = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &sampleRate)
        guard status == noErr, sampleRate > 0 else { return nil }
        return sampleRate
    }

    private static func sampleRateDescription(_ sampleRate: Double?) -> String {
        guard let sampleRate else { return "unknown" }
        let rounded = sampleRate.rounded()
        if abs(sampleRate - rounded) < 0.01 {
            return "\(Int(rounded))"
        }
        return String(format: "%.2f", sampleRate)
    }

    private static func transportType(for deviceID: AudioDeviceID) -> AudioDeviceTransport {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport = UInt32(kAudioDeviceTransportTypeUnknown)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &transport)
        guard status == noErr else { return .unknown }
        return AudioDeviceTransport.fromCoreAudioTransportType(transport)
    }

    // MARK: - AudioRecording conformance

    enum RecordingError: Error {
        case formatConversionFailed
        case audioFormatUnavailable
        case conversionFailed(errorCount: Int)
        case recordingTooLong
        case deviceSelectionFailed
    }

    private struct CapturedAudio {
        let buffers: [AVAudioPCMBuffer]
        let conversionErrorCount: Int
    }
}

// MARK: - AudioRecording conformance

extension AudioRecorder: AudioRecording {}
