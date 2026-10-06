import AppKit
import SwiftUI

struct VocabularyApprovalInboxView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var pendingProposals: [VocabularyProposal] {
        appState.agentAccessProposals.filter { $0.state == .pending }
    }

    private var pendingActions: [AgentAccessActionRecord] {
        appState.agentAccessActions.filter { $0.state == .pending || $0.state == .approvedPendingApply }
    }

    var body: some View {
        NavigationStack {
            Group {
                if pendingProposals.isEmpty && pendingActions.isEmpty {
                    ContentUnavailableView(
                        "No pending Vocabulary approvals",
                        systemImage: "checkmark.shield",
                        description: Text("Agent requests to change Vocabulary will appear here.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if !pendingProposals.isEmpty {
                                Text("Corrections").font(.headline)
                                ForEach(pendingProposals) { proposal in
                                    VocabularyProposalEditorCard(appState: appState, proposal: proposal)
                                }
                            }
                            if !pendingActions.isEmpty {
                                Text("Other Vocabulary requests").font(.headline)
                                ForEach(pendingActions) { record in
                                    AgentAccessActionCard(appState: appState, record: record)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Vocabulary approvals")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("agentApprovals.done")
                }
            }
        }
        .frame(minWidth: 680, minHeight: 520)
        .background(FoilTheme.windowBackground)
        .accessibilityIdentifier("agentApprovals.reviewView")
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

    private var hasPendingRescopeRequest: Bool {
        appState.agentAccessActions.contains {
            $0.request.action == .rescopeProposal && $0.request.proposalID == proposal.id &&
                ($0.state == .pending || $0.state == .approvedPendingApply)
        }
    }

    private var canApply: Bool {
        canSave
            && !hasUnsavedEdits
            && preview?.valid == true
            && !hasPendingRescopeRequest
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
                        "Vocabulary changed after this proposal arrived. Foil revalidates it against the current state before applying.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                if hasPendingRescopeRequest {
                    Label(
                        "An agent requested a scope change for this proposal. Review or reject that action before applying these corrections in the current scope.",
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

private struct AgentAccessActionCard: View {
    @Bindable var appState: AppState
    let record: AgentAccessActionRecord

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Agent requests a change", systemImage: "checkmark.shield")
                        .font(.headline)
                    Spacer()
                    Text(record.createdAt, style: .relative).foregroundStyle(.secondary)
                }
                actionDetail(record)
                Text("Request ID: \(record.request.requestID)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let message = appState.agentAccessActionErrorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Button(record.state == .approvedPendingApply ? "Retry approved change" : "Approve change") {
                        appState.decideAgentAccessAction(id: record.id, approve: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApprove(record))
                    .accessibilityIdentifier("agentActions.approve.\(record.id)")
                    Button(record.state == .approvedPendingApply ? "Stop retrying" : "Reject", role: .destructive) {
                        appState.decideAgentAccessAction(id: record.id, approve: false)
                    }
                    .accessibilityIdentifier("agentActions.reject.\(record.id)")
                }
                if record.state == .approvedPendingApply {
                    Text("Your approval was saved, but Foil has not confirmed the change. Retry after resolving the error. Stopping retries does not undo a change that may already have applied.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(4)
        }
        .accessibilityIdentifier("agentActions.card.\(record.id)")
    }

    @ViewBuilder
    private func actionDetail(_ record: AgentAccessActionRecord) -> some View {
        let request = record.request
        switch request.action {
        case .applyProposal:
            if let proposal = appState.agentAccessProposals.first(where: { $0.id == request.proposalID }) {
                Text("Apply this Vocabulary proposal in \(scopeName(proposal.scope.id)):")
                    .font(.subheadline.weight(.semibold))
                ForEach(Array(proposal.corrections.enumerated()), id: \.offset) { _, correction in
                    Text("\(correction.spokenForms.joined(separator: ", ")) → \(correction.replacement)\(correction.caseSensitive ? " (case sensitive)" : "")")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                if let preview = appState.agentAccessProposalPreviews[proposal.id], !preview.valid {
                    ForEach(Array(preview.issues.enumerated()), id: \.offset) { _, issue in
                        Label(issue.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                if (proposal.reviewHash ?? proposal.requestHash) != record.targetDigest {
                    Label("This proposal changed after the action request. Apply it in the proposal review, or ask the agent for a new request.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                if record.state == .approvedPendingApply,
                   appState.appliedVocabularyProposalReceipts.contains(where: {
                       $0.proposalID == proposal.id && $0.requestID == proposal.requestID
                   }) {
                    Text("This proposal is already in Vocabulary. Retry records the completed change in the action audit.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Applying saves exact local corrections. It does not turn on local corrections.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Label("The proposal is unavailable.", systemImage: "exclamationmark.triangle")
            }
        case .createCleanupGroup:
            Text("Create an enabled Cleanup Group: \(request.groupName ?? "")")
                .font(.subheadline.weight(.semibold))
            Text("Assign only these installed app paths:")
            ForEach(request.appPaths ?? [], id: \.self) { path in
                Text(path).font(.body.monospaced()).textSelection(.enabled)
                if let existingGroup = AgentAccessAppTargeting.pathAssignmentConflict(
                    path: path, destinationGroupID: record.id, groups: appState.cleanupGroups
                ) {
                    Label("Already assigned to \(existingGroup.name). Remove that assignment in Settings before approving this request.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Text("This group starts with Foil's standard raw cleanup settings. Assigning an app changes its Cleanup Group routing and where scoped local corrections run.")
                .font(.caption).foregroundStyle(.secondary)
            if (try? AgentAccessAppTargeting.resolve(paths: request.appPaths ?? [])) == nil {
                Label("An app path is unavailable or cannot be assigned on this Mac.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        case .rescopeProposal:
            if let proposal = appState.agentAccessProposals.first(where: { $0.id == request.proposalID }) {
                Text("Replace this proposal's scope: \(scopeName(proposal.scope.id)) → \(scopeName(request.groupID ?? ""))")
                    .font(.subheadline.weight(.semibold))
                ForEach(Array(proposal.corrections.enumerated()), id: \.offset) { _, correction in
                    Text("\(correction.spokenForms.joined(separator: ", ")) → \(correction.replacement)")
                        .font(.body.monospaced()).textSelection(.enabled)
                }
                Text("Requested app paths:").font(.caption.weight(.semibold))
                ForEach(request.appPaths ?? [], id: \.self) { path in
                    Text(path).font(.caption.monospaced()).textSelection(.enabled)
                }
                Text("This changes the pending proposal in place. It does not apply the corrections; review and apply the proposal separately.")
                    .font(.caption).foregroundStyle(.secondary)
                if (proposal.reviewHash ?? proposal.requestHash) != record.targetDigest &&
                   (proposal.reviewHash ?? proposal.requestHash) != record.resultDigest {
                    Label("The proposal changed after this request. Ask the agent for a new scope request.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            } else {
                Label("The proposal is unavailable.", systemImage: "exclamationmark.triangle")
            }
        case .setLocalCorrectionsEnabled:
            Text(request.enabled == true ? "Turn on local corrections on this Mac" : "Turn off local corrections on this Mac")
                .font(.subheadline.weight(.semibold))
            Text("Current: \(appState.localCorrectionSnapshot.isEnabled ? "On" : "Off") · Requested: \(request.enabled == true ? "On" : "Off")")
            Text("Scope: all enabled exact local correction rules; each rule still keeps its own app or Cleanup Group scope.")
                .font(.caption).foregroundStyle(.secondary)
        case .setCorrectionScope:
            if let correction = appState.vocabularyCorrections.first(where: {
                $0.id.uuidString.lowercased() == request.correctionID?.lowercased()
            }) {
                Text("Set exact correction scope: \(correction.writtenAs) → \(correction.correctVersion)")
                    .font(.subheadline.weight(.semibold))
                Text("Requested scope: \(scopeName(request.scopeID ?? ""))")
                let current = appState.localCorrectionRule(forVocabularyCorrectionID: correction.id)
                Text("Current scope: \(current.map { scopeName($0.group ?? "global") } ?? "No local rule")")
                    .font(.caption).foregroundStyle(.secondary)
                Text("The correction stays \(current?.enabled == true ? "On" : "Off"). Use a policy request to change its On/Off state.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Label("The correction is unavailable.", systemImage: "exclamationmark.triangle")
            }
        case .setCorrectionPolicies:
            Text("Change exact local correction policies")
                .font(.subheadline.weight(.semibold))
            ForEach(request.correctionPolicies ?? [], id: \.correctionID) { policy in
                if let correction = appState.vocabularyCorrections.first(where: {
                    $0.id.uuidString.lowercased() == policy.correctionID
                }) {
                    let current = appState.localCorrectionRule(forVocabularyCorrectionID: correction.id)
                    let currentScope = current.map { scopeName($0.group ?? "global") } ?? "No local rule"
                    let currentExceptions = appState.localCorrectionSnapshot.rules
                        .filter { $0.id.hasPrefix("suppression:\(policy.correctionID):") && $0.suppressesGlobal }
                        .compactMap(\.group)
                        .sorted()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(correction.writtenAs) → \(correction.correctVersion)")
                            .font(.body.monospaced()).textSelection(.enabled)
                        Text("Current: \(current?.enabled == true ? "On" : "Off") · \(currentScope) · \(current?.caseSensitive == true ? "Case sensitive" : "Case insensitive")")
                        Text("Requested: \(policy.enabled ? "On" : "Off") · \(scopeName(policy.scopeID)) · \(policy.caseSensitive ? "Case sensitive" : "Case insensitive")")
                        Text("Current exceptions: \(currentExceptions.isEmpty ? "None" : currentExceptions.map(scopeName).joined(separator: ", "))")
                        Text("Requested exceptions: \(policy.suppressedGroupIDs.isEmpty ? "None" : policy.suppressedGroupIDs.map(scopeName).joined(separator: ", "))")
                    }
                    .font(.caption)
                } else {
                    Label("A requested correction is unavailable (\(policy.correctionID)).", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            if let enabled = request.enabled {
                Text("Local corrections switch: \(appState.localCorrectionSnapshot.isEnabled ? "On" : "Off") → \(enabled ? "On" : "Off")")
                    .font(.caption.weight(.semibold))
            } else {
                Text("Local corrections switch stays \(appState.localCorrectionSnapshot.isEnabled ? "On" : "Off").")
                    .font(.caption)
            }
            if let model = try? AgentAccessPolicyBatchPlanner.digest(
                model: AgentAccessController.makeReadModel(from: appState), groups: appState.cleanupGroups
            ), model != record.targetDigest && model != record.resultDigest {
                Label("Vocabulary or app routing changed after this request. Ask the agent for a new policy request.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Text("Approving applies every listed policy together. No change is made until you approve inside Foil.")
                .font(.caption).foregroundStyle(.secondary)
        case .assignAppToGroup:
            let bundleID = request.appBundleID ?? ""
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            Text("Assign \(bundleID) to \(scopeName(request.groupID ?? ""))")
                .font(.subheadline.weight(.semibold))
            Text("App: \(appURL?.path ?? "Not installed on this Mac")")
                .font(.caption.monospaced()).textSelection(.enabled)
            if let appURL {
                let displayName = (Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? appURL.deletingPathExtension().lastPathComponent
                let context = CleanupAppContext(
                    displayName: displayName, bundleIdentifier: bundleID, appPath: appURL.path
                )
                Text("Current Cleanup Group: \(appState.resolveCleanupGroup(for: context).group.name)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("This changes the app's Cleanup Group routing, including that group's cleanup settings and scoped local corrections.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func canApprove(_ record: AgentAccessActionRecord) -> Bool {
        let request = record.request
        switch request.action {
        case .applyProposal:
            guard let proposal = appState.agentAccessProposals.first(where: { $0.id == request.proposalID }) else {
                return false
            }
            guard (proposal.reviewHash ?? proposal.requestHash) == record.targetDigest else {
                return false
            }
            if record.state == .approvedPendingApply,
               appState.appliedVocabularyProposalReceipts.contains(where: {
                   $0.proposalID == proposal.id && $0.requestID == proposal.requestID
               }) {
                return true
            }
            return proposal.state == .pending && appState.agentAccessProposalPreviews[proposal.id]?.valid == true
        case .createCleanupGroup:
            guard let name = request.groupName,
                  let paths = request.appPaths,
                  let targets = try? AgentAccessAppTargeting.resolve(paths: paths),
                  !appState.cleanupGroups.contains(where: {
                      $0.id != record.id && $0.name.caseInsensitiveCompare(name) == .orderedSame
                  }) else { return false }
            if let existing = appState.cleanupGroups.first(where: { $0.id == record.id }),
               !AgentAccessAppTargeting.canResumeCreation(existing, name: name, paths: paths) {
                return false
            }
            return targets.allSatisfy { target in
                AgentAccessAppTargeting.pathAssignmentConflict(
                    path: target.path, destinationGroupID: record.id, groups: appState.cleanupGroups
                ) == nil && !appState.cleanupGroups.contains { group in
                    group.id != record.id && group.appMatchers.contains { matcher in
                        matcher.bundleIdentifier?.caseInsensitiveCompare(target.bundleID) == .orderedSame
                    }
                }
            }
        case .rescopeProposal:
            guard let proposal = appState.agentAccessProposals.first(where: { $0.id == request.proposalID }),
                  let groupID = request.groupID,
                  let paths = request.appPaths,
                  let group = appState.cleanupGroups.first(where: { $0.id == groupID }),
                  AgentAccessAppTargeting.hasExactlyThesePaths(group, paths: paths),
                  let targets = try? AgentAccessAppTargeting.resolve(paths: paths),
                  targets.allSatisfy({ appState.resolveCleanupGroup(for: $0.context).group.id == groupID }) else {
                return false
            }
            let digest = proposal.reviewHash ?? proposal.requestHash
            return (proposal.state == .pending && digest == record.targetDigest)
                || (record.state == .approvedPendingApply && proposal.scope.id == groupID
                    && digest == record.resultDigest)
        case .setLocalCorrectionsEnabled:
            return request.enabled != nil
        case .setCorrectionScope:
            return appState.vocabularyCorrections.contains {
                $0.id.uuidString.lowercased() == request.correctionID?.lowercased()
            } && (request.scopeID == "global" || appState.cleanupGroups.contains {
                $0.id == request.scopeID && $0.isEnabled
            })
        case .setCorrectionPolicies:
            let model = AgentAccessController.makeReadModel(from: appState)
            let groups = appState.cleanupGroups
            guard let current = try? AgentAccessPolicyBatchPlanner.digest(model: model, groups: groups) else {
                return false
            }
            if record.state == .approvedPendingApply && current == record.resultDigest { return true }
            guard current == record.targetDigest,
                  let plan = try? AgentAccessPolicyBatchPlanner.plan(request, model: model, groups: groups) else {
                return false
            }
            return plan.resultDigest == record.resultDigest
        case .assignAppToGroup:
            guard let bundleID = request.appBundleID,
                  let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                return false
            }
            return Bundle(url: appURL)?.bundleIdentifier == bundleID && appState.cleanupGroups.contains {
                $0.id == request.groupID && $0.isEnabled
            }
        }
    }

    private func scopeName(_ id: String) -> String {
        if id == "global" { return "Every app" }
        guard let group = appState.cleanupGroups.first(where: { $0.id == id }) else {
            return "Unavailable Cleanup Group (\(id))"
        }
        return group.isDefault ? "Unassigned apps" : group.name
    }
}
