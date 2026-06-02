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
}
