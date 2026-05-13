import Foundation

/// Serializes paste operations so concurrent transcription completions
/// don't fight over window focus. Jobs execute in FIFO order.
actor PasteQueue {
    typealias PasteHandler = @Sendable (String, PasteTarget, Bool) async -> PasteDelivery

    private struct Job {
        let text: String
        let target: PasteTarget
        let keepOnClipboard: Bool
        let continuation: CheckedContinuation<PasteDelivery?, Never>
    }

    private let handler: PasteHandler
    private var jobs: [Job] = []
    private var isDraining = false

    init(handler: @escaping PasteHandler) {
        self.handler = handler
    }

    func enqueue(text: String, target: PasteTarget, keepOnClipboard: Bool) async -> PasteDelivery? {
        guard target.isValid else { return nil }
        return await withCheckedContinuation { continuation in
            jobs.append(Job(text: text, target: target, keepOnClipboard: keepOnClipboard, continuation: continuation))
            startDrainingIfNeeded()
        }
    }

    private func startDrainingIfNeeded() {
        guard !isDraining else { return }
        isDraining = true
        Task { await drain() }
    }

    private func drain() async {
        while let job = nextJob() {
            let delivery = await handler(job.text, job.target, job.keepOnClipboard)
            job.continuation.resume(returning: delivery)
        }

        isDraining = false
        if !jobs.isEmpty {
            startDrainingIfNeeded()
        }
    }

    private func nextJob() -> Job? {
        guard !jobs.isEmpty else { return nil }
        return jobs.removeFirst()
    }
}
