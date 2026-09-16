import SwiftUI

struct ManagedLocalSetupView: View {
    enum Context { case onboarding, settings }

    @Bindable var appState: AppState
    var context: Context = .settings
    @State private var lastRequestedID: String?
    @State private var actionError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var coordinator: ManagedLocalModelCoordinator? { appState.managedLocalModels }
    private var catalog: ManagedLocalModelCatalog? { coordinator?.store.catalog }
    private var recommendation: ManagedLocalModelCatalog.Model? {
        catalog?.recommendation(for: appState.managedDictationLanguage)
    }
    private var status: ManagedLocalPresentation.Status {
        ManagedLocalPresentation.status(
            coordinatorState: coordinator?.state,
            selectedID: coordinator?.selectedID,
            activeID: coordinator?.activeID,
            candidateID: coordinator?.candidateID,
            recovery: coordinator?.recovery ?? [],
            externalError: appState.managedLocalRestoreError
        )
    }
    private var isBusy: Bool {
        guard let coordinator else { return false }
        switch coordinator.state {
        case .recovering, .downloading, .verifying, .starting: return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(context == .onboarding ? "Choose your dictation languages" : "Managed local models")
                .font(.headline)
            Text("Foil downloads a verified model only after you choose Install. No account or API key is needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Languages", selection: $appState.managedDictationLanguage) {
                Text("Choose…").tag(ManagedDictationLanguage.unanswered)
                Text("English only").tag(ManagedDictationLanguage.englishOnly)
                Text("Other or multiple languages").tag(ManagedDictationLanguage.multilingual)
            }
            .accessibilityIdentifier("managedLocal.languagePicker")
            .disabled(isBusy)

            if let recommendation {
                recommendationCard(recommendation)
            } else {
                Text("Choose your language needs before Foil recommends a model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("managedLocal.languagePrompt")
            }

            statusView(status)

            installedModels

            if let actionError {
                Label(actionError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(FoilTheme.statusWarning)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("managedLocal.actionError")
            }

            Text("Service: \(ManagedLocalPresentation.serviceAddress) · no API key")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .accessibilityIdentifier("managedLocal.serviceAddress")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("managedLocal.setup")
    }

    @ViewBuilder
    private func recommendationCard(_ model: ManagedLocalModelCatalog.Model) -> some View {
        let installed = coordinator?.installed.contains { $0.id == model.id } == true
        VStack(alignment: .leading, spacing: 6) {
            Text("Recommended: \(ManagedLocalPresentation.name(for: model.id))")
                .font(.callout.weight(.semibold))
                .accessibilityIdentifier("managedLocal.recommendation")
            Text("Download and installed size: \(ManagedLocalPresentation.downloadSize(for: model)). During installation Foil also needs \(ManagedLocalPresentation.temporarySpace(for: model)) temporary space (\(ManagedLocalPresentation.requiredSpace(for: model)) total free space).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("managedLocal.modelSizes")
            Button(installed ? "Use \(ManagedLocalPresentation.name(for: model.id))" : "Install \(ManagedLocalPresentation.name(for: model.id))") {
                install(model.id)
            }
            .buttonStyle(.borderedProminent)
            .tint(FoilTheme.deepTeal)
            .disabled(isBusy || coordinator?.activeID == model.id)
            .accessibilityIdentifier("managedLocal.installRecommended")
        }
        .padding(10)
        .background(FoilTheme.sidebarBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func statusView(_ status: ManagedLocalPresentation.Status) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(status.title, systemImage: status.isReady ? "checkmark.circle.fill" : "arrow.down.circle")
                .font(.callout.weight(.semibold))
                .foregroundStyle(status.isReady ? FoilTheme.statusSuccess : .primary)
                .accessibilityIdentifier("managedLocal.statusTitle")
            Text(status.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("managedLocal.statusDetail")
            if let progress = status.progress {
                ProgressView(value: progress)
                    .accessibilityLabel("Model download progress")
                    .accessibilityValue(status.detail)
                    .accessibilityIdentifier("managedLocal.downloadProgress")
            } else if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(status.title)
                    .accessibilityValue("In progress")
            }
            HStack {
                if isBusy {
                    Button("Cancel") { appState.cancelManagedLocalModelOperation() }
                        .accessibilityIdentifier("managedLocal.cancel")
                }
                if status.canRetry {
                    Button("Retry") { retry() }
                        .disabled(isBusy || retryID == nil)
                        .accessibilityIdentifier("managedLocal.retry")
                }
                if !status.isReady, coordinator?.selectedID != nil, !isBusy {
                    Button("Restore selected model") { restore() }
                        .accessibilityIdentifier("managedLocal.restore")
                }
                Button("Test connection") { testConnection() }
                    .disabled(!status.isReady || appState.providerConnectionTestState.isRunning)
                    .accessibilityIdentifier("managedLocal.testConnection")
            }
            connectionStatus
        }
        .animation(reduceMotion ? nil : .default, value: status)
    }

    @ViewBuilder
    private var installedModels: some View {
        if let coordinator, !coordinator.installed.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Installed models").font(.caption.weight(.semibold))
                ForEach(coordinator.installed, id: \.id) { model in
                    let reason = ManagedLocalPresentation.removalReason(
                        id: model.id,
                        selectedID: coordinator.selectedID,
                        activeID: coordinator.activeID,
                        candidateID: coordinator.candidateID,
                        protectedIDs: coordinator.runtime.protectedModelIDs
                    )
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ManagedLocalPresentation.name(for: model.id))
                            Text(identityDetail(model.id, coordinator: coordinator))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if coordinator.activeID != model.id {
                            Button("Use") { install(model.id) }
                                .disabled(isBusy)
                                .accessibilityIdentifier("managedLocal.use.\(model.id)")
                        }
                        Button("Remove", role: .destructive) { remove(model.id) }
                            .disabled(isBusy || reason != nil)
                            .help(reason ?? "Remove this inactive model")
                            .accessibilityIdentifier("managedLocal.remove.\(model.id)")
                    }
                }
            }
            .accessibilityIdentifier("managedLocal.installedModels")
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        switch appState.providerConnectionTestState {
        case .idle: EmptyView()
        case .running: ProgressView("Testing owned session…").controlSize(.small)
        case .succeeded(let message):
            Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(FoilTheme.statusSuccess)
        case .warning(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(FoilTheme.statusWarning)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill").foregroundStyle(FoilTheme.statusWarning)
        }
    }

    private var retryID: String? {
        lastRequestedID ?? coordinator?.selectedID ?? recommendation?.id
    }

    private func install(_ id: String) {
        lastRequestedID = id
        actionError = nil
        Task { @MainActor in
            do { try await appState.installAndSelectManagedLocalModel(id) }
            catch is CancellationError { }
            catch { actionError = error.localizedDescription }
        }
    }

    private func retry() {
        guard let retryID else { return }
        install(retryID)
    }

    private func restore() {
        actionError = nil
        Task { @MainActor in
            do { try await appState.restoreManagedLocalModel() }
            catch is CancellationError { }
            catch { actionError = error.localizedDescription }
        }
    }

    private func testConnection() {
        Task { @MainActor in await appState.testSelectedProviderConnection() }
    }

    private func remove(_ id: String) {
        actionError = nil
        Task { @MainActor in
            do { try await appState.removeManagedLocalModel(id) }
            catch { actionError = error.localizedDescription }
        }
    }

    private func identityDetail(_ id: String, coordinator: ManagedLocalModelCoordinator) -> String {
        var labels = ["Installed"]
        if coordinator.selectedID == id { labels.append("Selected") }
        if coordinator.activeID == id { labels.append("Active") }
        if coordinator.candidateID == id { labels.append("Candidate") }
        return labels.joined(separator: " · ")
    }
}
