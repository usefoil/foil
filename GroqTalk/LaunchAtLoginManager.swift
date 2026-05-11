import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginManager {
    private(set) var isEnabled: Bool

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isEnabled = enabled
        } catch {
            DiagnosticLog.write("Launch at login toggle failed: \(error.localizedDescription)")
        }
    }

    func refreshStatus() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
