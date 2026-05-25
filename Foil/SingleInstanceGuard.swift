import AppKit

/// Checks whether another instance of this app is already running
/// and, if so, attempts to activate it.
protocol SingleInstanceGuarding {
    /// If another instance is running, activates it and returns `true`; otherwise returns `false`.
    func activateExistingInstanceIfRunning() -> Bool
}

/// Default guard that detects duplicates by comparing running processes with the same bundle identifier.
struct SingleInstanceGuard: SingleInstanceGuarding {
    func activateExistingInstanceIfRunning() -> Bool {
        let myPID = ProcessInfo.processInfo.processIdentifier
        guard let bundleID = Bundle.main.bundleIdentifier else {
            DiagnosticLog.write("SingleInstanceGuard: bundleIdentifier is nil — cannot check for duplicates")
            return false
        }
        guard let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.processIdentifier != myPID && !$0.isTerminated }) else {
            return false
        }
        let activated = existing.activate()
        NSLog("[Foil] Another instance already running (pid %d), activated=%d — terminating duplicate.",
              existing.processIdentifier, activated ? 1 : 0)
        DiagnosticLog.write("Another instance already running (pid \(existing.processIdentifier)), activate=\(activated)")
        return true
    }
}
