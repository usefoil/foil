import SwiftUI

struct VocabularyBatchReviewCard: View {
    @Bindable var appState: AppState
    let record: VocabularyBatchRecord
    @State private var scopeID: String
    @State private var items: [ItemDraft]

    init(appState: AppState, record: VocabularyBatchRecord) {
        self.appState = appState
        self.record = record
        _scopeID = State(initialValue: record.reviewedRequest.scope.id)
        _items = State(initialValue: record.reviewedRequest.items.map(ItemDraft.init))
    }

    private var request: VocabularyBatchRequest {
        .init(requestID: record.originalRequest.requestID,
              scope: .init(kind: scopeID == "global" ? "global" : "cleanup_group", id: scopeID),
              items: items.map(\.item), reason: record.reviewedRequest.reason)
    }
    private var hasEdits: Bool { request.normalized() != record.reviewedRequest }
    private var preview: VocabularyBatchPreview? { appState.agentAccessBatchPreviews[record.id] }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Vocabulary changes", systemImage: "text.book.closed").font(.headline)
                if let reason = record.reviewedRequest.reason { Text(reason).font(.caption) }
                Picker("Apply in", selection: $scopeID) {
                    Text("Everywhere").tag("global")
                    ForEach(appState.cleanupGroups.filter(\.isEnabled)) { group in Text(group.name).tag(group.id) }
                }
                .accessibilityIdentifier("agentBatches.scope.\(record.id)")
                ForEach($items) { $item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(item.kind == .preferredTerm ? "Preferred spelling" : "Correction").font(.subheadline.bold())
                            Spacer()
                            Button("Omit", role: .destructive) { items.removeAll { $0.id == item.id } }
                                .accessibilityIdentifier("agentBatches.omit.\(item.id)")
                        }
                        TextField(item.kind == .preferredTerm ? "Preferred spelling" : "Replacement", text: $item.text)
                            .accessibilityIdentifier("agentBatches.text.\(item.id)")
                        if item.kind == .correction {
                            Text("Spoken forms, one per line").font(.caption)
                            TextEditor(text: $item.spokenForms).frame(height: 60)
                            Toggle("Case sensitive", isOn: $item.caseSensitive)
                            Toggle("Match punctuation between words", isOn: $item.punctuation)
                        }
                        TextField("Note (optional)", text: $item.note)
                        if item.kind == .preferredTerm && scopeID != "global" {
                            Toggle("Keep a separate scoped entry if already global", isOn: $item.independentScope)
                        }
                        if !hasEdits, let row = preview?.items.first(where: { $0.id == item.id }) {
                            Text(row.message).font(.caption)
                                .foregroundStyle(row.disposition == .conflict || row.disposition == .invalid ? Color.orange : Color.secondary)
                            ForEach(Array(row.examples.enumerated()), id: \.offset) { _, example in
                                Text("\(example.input) → \(example.output)").font(.caption.monospaced())
                            }
                        }
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                }
                if let preview, !hasEdits {
                    ForEach(preview.issues, id: \.self) { Text($0).foregroundStyle(.orange).font(.caption) }
                }
                Text("Foil revalidates selected items against the current Vocabulary before saving the whole batch.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Preferred spellings guide cleanup. Corrections replace matching text. This request does not turn cleanup or local corrections on.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = appState.agentAccessBatchErrorMessage {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("agentBatches.error")
                }
                HStack {
                    Button("Apply selected") { appState.agentAccessBatchApplyDidRequest?(record.id, request) }
                        .buttonStyle(.borderedProminent)
                        .disabled(items.isEmpty || (!hasEdits && preview?.valid != true))
                        .accessibilityIdentifier("agentBatches.apply.\(record.id)")
                    Button("Save review edits") { appState.agentAccessBatchRevisionDidRequest?(record.id, request) }
                        .disabled(items.isEmpty || !hasEdits)
                    Spacer()
                    Button("Reject", role: .destructive) { appState.agentAccessBatchTransitionDidRequest?(record.id, .rejected) }
                    Button("Discard") { appState.agentAccessBatchTransitionDidRequest?(record.id, .discarded) }
                }
            }
            .padding(4)
        }
        .accessibilityIdentifier("agentBatches.card.\(record.id)")
    }

    private struct ItemDraft: Identifiable {
        let id: String
        let kind: VocabularyBatchItem.Kind
        var text: String
        var note: String
        var spokenForms: String
        var caseSensitive: Bool
        var punctuation: Bool
        var independentScope: Bool

        init(_ item: VocabularyBatchItem) {
            id = item.id; kind = item.kind
            text = item.term ?? item.correction?.replacement ?? ""
            note = item.note ?? item.correction?.note ?? ""
            spokenForms = item.correction?.spokenForms.joined(separator: "\n") ?? ""
            caseSensitive = item.correction?.caseSensitive ?? false
            punctuation = item.correction?.matchPunctuationVariants ?? false
            independentScope = item.independentScope == true
        }
        var item: VocabularyBatchItem {
            if kind == .preferredTerm {
                return .init(id: id, kind: kind, term: text, note: note, independentScope: independentScope ? true : nil)
            }
            return .init(id: id, kind: kind, correction: .init(spokenForms: spokenForms.components(separatedBy: .newlines), replacement: text, note: note, caseSensitive: caseSensitive, matchPunctuationVariants: punctuation))
        }
    }
}
