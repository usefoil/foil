import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            DiagnosticLog.write("Notification authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    func postTranscriptionStarted() {
        let content = UNMutableNotificationContent()
        content.title = "Transcribing..."
        content.body = "Your recording is being processed"
        content.sound = nil  // silent — don't interrupt

        let request = UNNotificationRequest(
            identifier: "transcription-started",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                DiagnosticLog.write("Notification delivery failed: \(error.localizedDescription)")
            }
        }
    }

    func postTranscriptionComplete(preview: String) {
        // Remove the "started" notification so this one replaces it
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["transcription-started"])

        let content = UNMutableNotificationContent()
        content.title = "Transcription Complete"
        content.body = String(preview.prefix(100))
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "transcription-complete",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                DiagnosticLog.write("Notification delivery failed: \(error.localizedDescription)")
            }
        }
    }

    func postTranscriptionFailed(errorMessage: String) {
        let content = UNMutableNotificationContent()
        content.title = "Transcription Failed"
        content.body = errorMessage
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                DiagnosticLog.write("Notification delivery failed: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
