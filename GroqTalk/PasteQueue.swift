import Foundation

/// Serializes paste operations so concurrent transcription completions
/// don't fight over window focus. Jobs execute in FIFO order.
actor PasteQueue {
    typealias PasteHandler = @Sendable (String, PasteTarget, Bool) async -> Void

    private let handler: PasteHandler

    init(handler: @escaping PasteHandler) {
        self.handler = handler
    }

    func enqueue(text: String, target: PasteTarget, keepOnClipboard: Bool) async {
        guard target.isValid else { return }
        await handler(text, target, keepOnClipboard)
    }
}
