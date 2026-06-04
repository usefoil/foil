import Foundation

enum BluetoothMicGuidance {
    static let shownDefaultsKey = "builtInMicBluetoothGuidanceShown"

    static func shouldShowNotice(
        selectedInputDevice: AudioRecorder.AudioDevice?,
        availableInputDevices: [AudioRecorder.AudioDevice],
        hasShownNotice: Bool
    ) -> Bool {
        !hasShownNotice && shouldShowSettingsGuidance(
            selectedInputDevice: selectedInputDevice,
            availableInputDevices: availableInputDevices
        )
    }

    static func shouldShowSettingsGuidance(
        selectedInputDevice: AudioRecorder.AudioDevice?,
        availableInputDevices: [AudioRecorder.AudioDevice]
    ) -> Bool {
        guard let selectedInputDevice, selectedInputDevice.transport == .builtIn else {
            return false
        }
        return availableInputDevices.contains { device in
            device.uid != selectedInputDevice.uid && device.transport.isBluetooth
        }
    }

    static func automaticFallbackDevice(
        selectedInputDeviceUID: String?,
        effectiveInputDevice: AudioRecorder.AudioDevice?,
        availableInputDevices: [AudioRecorder.AudioDevice]
    ) -> AudioRecorder.AudioDevice? {
        guard selectedInputDeviceUID == nil,
              let effectiveInputDevice,
              effectiveInputDevice.transport.isBluetooth else {
            return nil
        }
        let decision = AudioRecorder.inputPreparationDecision(
            selectedUID: nil,
            devices: availableInputDevices,
            defaultInputDeviceID: effectiveInputDevice.id
        )
        guard decision.reason == .avoidBluetoothDefault else {
            return nil
        }
        return decision.device
    }

    static func shouldWarnAboutBluetoothInput(
        selectedInputDeviceUID: String?,
        effectiveInputDevice: AudioRecorder.AudioDevice?,
        availableInputDevices: [AudioRecorder.AudioDevice]
    ) -> Bool {
        guard let effectiveInputDevice, effectiveInputDevice.transport.isBluetooth else {
            return false
        }
        return automaticFallbackDevice(
            selectedInputDeviceUID: selectedInputDeviceUID,
            effectiveInputDevice: effectiveInputDevice,
            availableInputDevices: availableInputDevices
        ) == nil
    }
}
