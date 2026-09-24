import SwiftUI

struct VocabularyProposalReviewView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var pending: [VocabularyProposal] {
        appState.agentAccessProposals.filter { $0.state == .pending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if pending.isEmpty {
                    ContentUnavailableView(
                        "No pending proposals",
                        systemImage: "tray",
                        description: Text("Agent proposals will appear here for review.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(pending) { proposal in
                                VocabularyProposalEditorCard(
                                    appState: appState,
                                    proposal: proposal
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Vocabulary proposals")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("agentProposals.done")
                }
            }
        }
        .frame(minWidth: 680, minHeight: 520)
        .accessibilityIdentifier("agentProposals.reviewView")
    }
}

private struct VocabularyProposalEditorCard: View {
    @Bindable var appState: AppState
    let proposal: VocabularyProposal
    @State private var draft: ProposalDraft

    init(appState: AppState, proposal: VocabularyProposal) {
        self.appState = appState
        self.proposal = proposal
        _draft = State(initialValue: ProposalDraft(proposal: proposal))
    }

    private var preview: AgentAccessPreviewResponse? {
        appState.agentAccessProposalPreviews[proposal.id]
    }

    private var enabledScopes: [CleanupGroup] {
        appState.cleanupGroups.filter(\.isEnabled)
    }

    private var canSave: Bool {
        !draft.corrections.isEmpty
            && draft.corrections.allSatisfy {
                !$0.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.spokenForms.isEmpty
                    && $0.spokenForms.allSatisfy {
                        !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
            }
    }

    private var reviewedScope: VocabularyProposalScope {
        draft.scopeID == ProposalDraft.globalScopeID
            ? VocabularyProposalScope(kind: "global", id: "global")
            : VocabularyProposalScope(kind: "cleanup_group", id: draft.scopeID)
    }

    private var reviewedCorrections: [VocabularyProposalCorrection] {
        draft.corrections.map { correction in
            let normalizedNote = correction.note.trimmingCharacters(in: .whitespacesAndNewlines)
            return VocabularyProposalCorrection(
                spokenForms: correction.spokenForms.map(\.value),
                replacement: correction.replacement,
                note: normalizedNote.isEmpty ? nil : normalizedNote,
                caseSensitive: correction.caseSensitive
            )
        }
    }

    private var hasUnsavedEdits: Bool {
        reviewedScope != proposal.scope || reviewedCorrections != proposal.corrections
    }

    private var canApply: Bool {
        canSave
            && !hasUnsavedEdits
            && preview?.valid == true
            && !appState.agentAccessStaleProposalIDs.contains(proposal.id)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Pending review", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    Text(proposal.createdAt, style: .relative)
                        .foregroundStyle(.secondary)
                }

                Picker("Scope", selection: $draft.scopeID) {
                    Text("Every app").tag(ProposalDraft.globalScopeID)
                    ForEach(enabledScopes) { group in
                        Text(group.isDefault ? "Unassigned apps" : group.name).tag(group.id)
                    }
                }
                .accessibilityIdentifier("agentProposals.scope.\(proposal.id)")

                if appState.agentAccessStaleProposalIDs.contains(proposal.id) {
                    Label(
                        "Vocabulary changed after this proposal arrived. Validation below uses the current state.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                ForEach($draft.corrections) { $correction in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Correction")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button("Omit correction", role: .destructive) {
                                draft.corrections.removeAll { $0.id == correction.id }
                            }
                            .buttonStyle(.borderless)
                        }
                        ForEach($correction.spokenForms) { $form in
                            HStack {
                                TextField("Spoken form", text: $form.value)
                                    .accessibilityLabel("Spoken form")
                                Button {
                                    correction.spokenForms.removeAll { $0.id == form.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Omit spoken form")
                                .accessibilityLabel("Omit spoken form")
                            }
                        }
                        Button("Add spoken form") {
                            correction.spokenForms.append(.init(value: ""))
                        }
                        .buttonStyle(.link)
                        TextField("Replacement", text: $correction.replacement)
                            .accessibilityLabel("Replacement")
                        TextField("Note (optional)", text: $correction.note)
                            .accessibilityLabel("Note")
                        Toggle("Case sensitive", isOn: $correction.caseSensitive)
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                }

                if let preview {
                    if preview.valid {
                        Label("Valid with the current correction engine", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        ForEach(Array(preview.issues.enumerated()), id: \.offset) { _, issue in
                            Label(issue.message, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    ForEach(Array(preview.examples.enumerated()), id: \.offset) { _, example in
                        Text("\(example.input) → \(example.output)")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if let message = appState.agentAccessProposalInboxErrorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("agentProposals.error")
                }

                HStack {
                    Button("Save review edits") { save() }
                        .disabled(!canSave || !hasUnsavedEdits)
                        .accessibilityIdentifier("agentProposals.save.\(proposal.id)")
                    Button("Apply reviewed corrections") {
                        appState.applyAgentAccessProposal(id: proposal.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApply)
                    .accessibilityIdentifier("agentProposals.apply.\(proposal.id)")
                    Spacer()
                    Button("Reject", role: .destructive) {
                        appState.transitionAgentAccessProposal(id: proposal.id, to: .rejected)
                    }
                    .accessibilityIdentifier("agentProposals.reject.\(proposal.id)")
                    Button("Discard") {
                        appState.transitionAgentAccessProposal(id: proposal.id, to: .discarded)
                    }
                    .accessibilityIdentifier("agentProposals.discard.\(proposal.id)")
                }

                Text(
                    appState.localCorrectionSnapshot.isEnabled
                        ? "Saving edits keeps this proposal pending until you apply it."
                        : "Local corrections are off. Applying saves these entries but does not turn them on."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
        .accessibilityIdentifier("agentProposals.card.\(proposal.id)")
        .onChange(of: proposal.updatedAt) { _, _ in
            draft = ProposalDraft(proposal: proposal)
        }
    }

    private func save() {
        appState.reviseAgentAccessProposal(
            id: proposal.id,
            scope: reviewedScope,
            corrections: reviewedCorrections
        )
    }
}

private struct ProposalDraft {
    static let globalScopeID = "__global__"

    var scopeID: String
    var corrections: [CorrectionDraft]

    init(proposal: VocabularyProposal) {
        scopeID = proposal.scope.kind == "global" ? Self.globalScopeID : proposal.scope.id
        corrections = proposal.corrections.map(CorrectionDraft.init)
    }
}

private struct CorrectionDraft: Identifiable {
    let id = UUID()
    var spokenForms: [SpokenFormDraft]
    var replacement: String
    var note: String
    var caseSensitive: Bool

    init(_ correction: VocabularyProposalCorrection) {
        spokenForms = correction.spokenForms.map { SpokenFormDraft(value: $0) }
        replacement = correction.replacement
        note = correction.note ?? ""
        caseSensitive = correction.caseSensitive
    }
}

private struct SpokenFormDraft: Identifiable {
    let id = UUID()
    var value: String
}
