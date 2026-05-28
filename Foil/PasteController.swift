import AppKit
import Foundation

// MARK: - Delegate protocol

@MainActor
protocol PasteControllerDelegate: AnyObject {
    /// Called when a paste operation completes.
    func pasteController(_ controller: PasteController, didPaste text: String, delivery: PasteDelivery)
}

// MARK: - PasteController

/// Owns paste routing logic: captures the async target window before recording,
/// routes transcribed text through the PasteQueue (async path) or TextInserter
/// (sync path), and notifies its delegate on completion.
@MainActor
final class PasteController {

    // MARK: Dependencies

    private let textInserter: TextInserter
    private let appState: AppState
    private(set) lazy var pasteQueue: PasteQueue = PasteQueue { [weak self] text, target, keepOnClipboard in
        guard let self else { return .clipboardFallback }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            DiagnosticLog.write("UITest paste queue: route=asyncQueued target=\(target.appName) bytes=\(text.utf8.count)")
            return .asyncQueued
        }
        return await self.textInserter.insertAsync(
            text: text,
            target: target,
            keepOnClipboard: keepOnClipboard,
            allowSkyLight: self.appState.experimentalSkyLightPasteEnabled
        )
    }

    // MARK: State

    private(set) var pendingTarget: PasteTarget?
    private(set) var pendingRecordingStartTime: Date?

    // MARK: Delegate

    weak var delegate: PasteControllerDelegate?

    // MARK: Init

    init(textInserter: TextInserter, appState: AppState) {
        self.textInserter = textInserter
        self.appState = appState
    }

    // MARK: - Target capture

    /// Captures the current frontmost window as the pending paste target,
    /// but only when async paste is enabled. Clears the target otherwise.
    func captureTarget() {
        let shouldCapture = appState.asyncPasteEnabled || appState.queuedPasteEnabled
        let capturedTarget = shouldCapture ? PasteTarget.captureCurrentTarget() : nil
        DiagnosticLog.write("PasteController.captureTarget: asyncEnabled=\(appState.asyncPasteEnabled) queuedEnabled=\(appState.queuedPasteEnabled) capturedTarget=\(String(describing: capturedTarget))")
        pendingTarget = capturedTarget
        pendingRecordingStartTime = shouldCapture ? Date() : nil
    }

    /// Nils the pending target without capturing a new one.
    func clearPendingTarget() {
        pendingTarget = nil
        pendingRecordingStartTime = nil
    }

    /// Sets a pre-captured paste target directly. Use this when the caller has
    /// already captured the target through other means (e.g. automation smoke).
    func setPendingTarget(_ target: PasteTarget?) {
        pendingTarget = target
        pendingRecordingStartTime = Date()
    }

    func consumePendingContext() -> (target: PasteTarget?, recordingStartTime: Date?) {
        let context = (pendingTarget, pendingRecordingStartTime)
        pendingTarget = nil
        pendingRecordingStartTime = nil
        return context
    }

    // MARK: - Paste routing

    /// Routes text through the PasteQueue if an async target is available,
    /// otherwise falls back to a direct insert into the current app.
    /// Notifies the delegate on completion.
    @discardableResult
    func paste(text: String) async -> PasteDelivery {
        let asyncOn = appState.asyncPasteEnabled
        let target = pendingTarget
        pendingTarget = nil
        pendingRecordingStartTime = nil
        DiagnosticLog.write("PasteController.paste: asyncOn=\(asyncOn) target=\(String(describing: target))")

        let delivery: PasteDelivery
        if asyncOn, let target {
            DiagnosticLog.write("ASYNC PATH: pasting into \(target.appName) pid=\(target.pid)")
            if let queued = await pasteQueue.enqueue(
                text: text,
                target: target,
                keepOnClipboard: appState.keepOnClipboard
            ) {
                delivery = queued
            } else {
                // Queue returned nil (invalid target) — fall back to direct insert
                delivery = await textInserter.insert(text: text, keepOnClipboard: appState.keepOnClipboard)
            }
        } else {
            DiagnosticLog.write("SYNC PATH: pasting into current app")
            delivery = await textInserter.insert(text: text, keepOnClipboard: appState.keepOnClipboard)
        }

        delegate?.pasteController(self, didPaste: text, delivery: delivery)
        return delivery
    }

    /// Always inserts directly into the current app, regardless of async settings.
    /// Used for pasteLastSuccess, history pastes, and retry paths.
    @discardableResult
    func pasteDirectly(text: String) async -> PasteDelivery {
        let delivery = await textInserter.insert(text: text, keepOnClipboard: appState.keepOnClipboard)
        delegate?.pasteController(self, didPaste: text, delivery: delivery)
        return delivery
    }

    @discardableResult
    func pasteQueued(text: String, target: PasteTarget) async -> PasteDelivery {
        DiagnosticLog.write("PasteController.pasteQueued: target=\(target.appName) pid=\(target.pid)")
        let delivery: PasteDelivery
        if let queued = await pasteQueue.enqueue(
            text: text,
            target: target,
            keepOnClipboard: appState.keepOnClipboard
        ) {
            delivery = queued
        } else {
            delivery = await textInserter.insert(text: text, keepOnClipboard: true)
        }
        delegate?.pasteController(self, didPaste: text, delivery: delivery)
        return delivery
    }
}
