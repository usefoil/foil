import Foundation
import Observation

enum QueuedPasteMode: String, CaseIterable, Identifiable {
    case stepThrough
    case drain

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stepThrough:
            "Step through queue"
        case .drain:
            "Drain queue"
        }
    }
}

enum QueuedPasteStatus: String, Equatable {
    case pending
    case pasted
    case failed
    case needsManualPaste

    var displayName: String {
        switch self {
        case .pending:
            "Pending"
        case .pasted:
            "Pasted"
        case .failed:
            "Failed"
        case .needsManualPaste:
            "Manual paste"
        }
    }
}

struct QueuedPasteItem: Identifiable {
    let id: UUID
    let text: String
    let recordingStartTime: Date
    let completionTime: Date
    let target: PasteTarget?
    var status: QueuedPasteStatus
    var failureReason: String?
    var lastDelivery: PasteDelivery?

    var targetName: String {
        guard let target else { return "Manual paste" }
        return target.appName.isEmpty ? "Unknown app" : target.appName
    }

    var previewText: String {
        if text.count <= 48 { return text }
        return String(text.prefix(48)) + "..."
    }

    var canDeliver: Bool {
        guard let target else { return false }
        return target.isValid && (status == .pending || status == .failed)
    }
}

@MainActor @Observable
final class QueuedPasteQueue {
    typealias DeliveryHandler = @MainActor (String, PasteTarget) async -> PasteDelivery

    private(set) var items: [QueuedPasteItem] = []
    private let deliveryHandler: DeliveryHandler

    init(deliveryHandler: @escaping DeliveryHandler) {
        self.deliveryHandler = deliveryHandler
    }

    var hasItems: Bool { !items.isEmpty }

    var pendingCount: Int {
        items.filter { $0.status == .pending }.count
    }

    var blockedCount: Int {
        items.filter { $0.status == .failed || $0.status == .needsManualPaste }.count
    }

    @discardableResult
    func enqueue(
        text: String,
        target: PasteTarget?,
        recordingStartTime: Date,
        completionTime: Date = Date()
    ) -> UUID {
        let status: QueuedPasteStatus
        let failureReason: String?
        if let target, target.isValid {
            status = .pending
            failureReason = nil
        } else {
            status = .needsManualPaste
            failureReason = "Original target unavailable"
        }

        let item = QueuedPasteItem(
            id: UUID(),
            text: text,
            recordingStartTime: recordingStartTime,
            completionTime: completionTime,
            target: target,
            status: status,
            failureReason: failureReason,
            lastDelivery: nil
        )
        items.append(item)
        sortByRecordingStart()
        DiagnosticLog.write("QueuedPaste.enqueue: status=\(status.rawValue) target=\(item.targetName) bytes=\(text.utf8.count) pending=\(pendingCount) blocked=\(blockedCount)")
        return item.id
    }

    @discardableResult
    func deliverNext() async -> PasteDelivery? {
        guard let item = nextDeliverableItem() else {
            DiagnosticLog.write("QueuedPaste.deliverNext: no pending item")
            return nil
        }
        return await deliver(id: item.id)
    }

    @discardableResult
    func drain() async -> [PasteDelivery] {
        var deliveries: [PasteDelivery] = []
        while let item = nextDeliverableItem() {
            if let delivery = await deliver(id: item.id) {
                deliveries.append(delivery)
            } else {
                break
            }
        }
        DiagnosticLog.write("QueuedPaste.drain: attempted=\(deliveries.count) pending=\(pendingCount) blocked=\(blockedCount)")
        return deliveries
    }

    @discardableResult
    func retry(id: UUID) async -> PasteDelivery? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        guard items[index].status == .failed || items[index].status == .needsManualPaste else { return nil }
        items[index].status = .pending
        items[index].failureReason = nil
        DiagnosticLog.write("QueuedPaste.retry: id=\(id.uuidString) target=\(items[index].targetName)")
        return await deliver(id: id)
    }

    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: index)
        DiagnosticLog.write("QueuedPaste.remove: id=\(id.uuidString) status=\(removed.status.rawValue) pending=\(pendingCount) blocked=\(blockedCount)")
    }

    func text(for id: UUID) -> String? {
        items.first(where: { $0.id == id })?.text
    }

    private func nextDeliverableItem() -> QueuedPasteItem? {
        items
            .filter { $0.status == .pending }
            .sorted { $0.recordingStartTime < $1.recordingStartTime }
            .first
    }

    @discardableResult
    private func deliver(id: UUID) async -> PasteDelivery? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        guard let target = items[index].target, target.isValid else {
            markNeedsManualPaste(id: id, reason: "Original target unavailable")
            return nil
        }

        let text = items[index].text
        let targetName = items[index].targetName
        DiagnosticLog.write("QueuedPaste.deliver: id=\(id.uuidString) target=\(targetName) bytes=\(text.utf8.count)")
        let delivery = await deliveryHandler(text, target)

        guard let deliveredIndex = items.firstIndex(where: { $0.id == id }) else {
            return delivery
        }
        items[deliveredIndex].lastDelivery = delivery

        if delivery == .clipboardFallback {
            items[deliveredIndex].status = .needsManualPaste
            items[deliveredIndex].failureReason = "Target unavailable; text copied to clipboard"
            DiagnosticLog.write("QueuedPaste.deliver: fallback id=\(id.uuidString) target=\(targetName)")
        } else {
            items[deliveredIndex].status = .pasted
            DiagnosticLog.write("QueuedPaste.deliver: pasted id=\(id.uuidString) delivery=\(delivery.label)")
            items.remove(at: deliveredIndex)
        }

        return delivery
    }

    private func markNeedsManualPaste(id: UUID, reason: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .needsManualPaste
        items[index].failureReason = reason
        DiagnosticLog.write("QueuedPaste.markNeedsManualPaste: id=\(id.uuidString) reason=\(reason)")
    }

    private func sortByRecordingStart() {
        items.sort { lhs, rhs in
            if lhs.recordingStartTime == rhs.recordingStartTime {
                return lhs.completionTime < rhs.completionTime
            }
            return lhs.recordingStartTime < rhs.recordingStartTime
        }
    }
}
