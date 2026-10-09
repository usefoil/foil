import SwiftUI
import AppKit

struct CodexCleanupView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var model = CodexCleanupModel()
    @State private var preferences = CodexCleanupPreferences(defaults: AppState.codexCleanupPreferencesDefaults)
    @State private var choices: [CodexCleanupModelChoice] = []
    @State private var isLoadingModels = false
    @State private var catalogError: String?
    @State private var showsInstructions = false
    @State private var showsTiming = false
    @State private var catalogRefresh = 0
    @State private var input = ""
    @State private var groupID = CleanupGroup.defaultGroupID
    @State private var executable = CodexTextCleanup.findExecutable()
    private var usesTestRunner: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
            && ProcessInfo.processInfo.arguments.contains("--mock-codex-cleanup")
        #else
        false
        #endif
    }
    private var hasRunner: Bool { executable != nil || usesTestRunner }
    private static let exampleID = "foil-cleanup-example"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Try transcript cleanup").font(.title2.bold())
                Spacer()
                Button("Done") { model.cancel(); dismiss() }
                    .accessibilityIdentifier("codexCleanup.done")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
            Text("Codex runs on this Mac and sends your entered text and selected Vocabulary to OpenAI’s hosted model. Each click runs one cleanup; it does not enable cleanup for recordings.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("codexCleanup.disclosure")
            HStack {
                Label(!hasRunner ? "Codex unavailable" : "Codex available · Starts per cleanup",
                      systemImage: !hasRunner ? "exclamationmark.circle" : "checkmark.circle")
                    .accessibilityIdentifier("codexCleanup.connection")
                Spacer()
                Button("Check again") { executable = CodexTextCleanup.findExecutable(); catalogRefresh += 1 }
                    .disabled(model.isRunning)
            }
            Text("Uses your Codex sign-in. Each cleanup starts and stops its own process; no cleanup server stays running. Model access is checked on each run.")
                .font(.caption).foregroundStyle(.secondary)
            configurationEditor
            HStack {
                Picker("Vocabulary", selection: $groupID) {
                    ForEach(appState.cleanupGroups.filter(\.isEnabled), id: \.id) { group in
                        Text(group.name).tag(group.id)
                    }
                    Text("Example: Supabase and Vercel").tag(Self.exampleID)
                }
                .accessibilityIdentifier("codexCleanup.scope")
                Button("Load example") {
                    groupID = Self.exampleID
                    input = CodexCleanupRequest.exampleText
                }
                .accessibilityIdentifier("codexCleanup.example")
            }
            .disabled(model.isRunning)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Original").font(.headline)
                    TextEditor(text: $input)
                        .font(.body)
                        .padding(6)
                        .background(.background)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                        .accessibilityIdentifier("codexCleanup.input")
                        .disabled(model.isRunning)
                    Text("\(input.utf8.count) / 8,192 bytes").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text("Cleaned").font(.headline)
                    ScrollView {
                        Text(model.result.map { Self.highlighted($0, comparedTo: input) }
                             ?? AttributedString("Your cleaned text will appear here."))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .accessibilityLabel(model.result ?? "Your cleaned text will appear here.")
                            .accessibilityIdentifier("codexCleanup.result")
                    }
                    .background(.background)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    Text(model.result == nil ? "Review the result before using it." : "Highlighted area contains changes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(height: 220)
            if let metrics = model.metrics { timingDetails(metrics) }
                }
            }
            if let error = model.error {
                Text(error).foregroundStyle(.red).font(.callout)
                    .accessibilityIdentifier("codexCleanup.error")
            }
            if !hasRunner {
                Text(CodexCleanupError.missingCodex.localizedDescription).font(.callout)
            }
            HStack {
                if model.isRunning {
                    ProgressView().controlSize(.small)
                    Text("Cleaning up…").accessibilityIdentifier("codexCleanup.running")
                    Button("Cancel") { model.cancel() }.accessibilityIdentifier("codexCleanup.cancel")
                } else {
                    Button("Clean up with Codex", action: run)
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasRunner || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || input.utf8.count > CodexCleanupRequest.maximumTextBytes
                                  || !configurationIsValid || isLoadingModels)
                        .accessibilityIdentifier("codexCleanup.run")
                }
                if let elapsed = model.elapsed { Text(String(format: "Completed in %.1f s", elapsed)).font(.caption) }
                Spacer()
                Button("Copy result") {
                    guard let result = model.result else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                }
                .disabled(model.result == nil)
                .accessibilityIdentifier("codexCleanup.copy")
            }
            Text("This experiment does not save text to Foil History or change Vocabulary. Model, reasoning and instructions are saved; closing discards the entered text and result. Recording and audio are not used.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 780, height: 760)
        .onChange(of: input) { _, _ in model.reset() }
        .onChange(of: groupID) { _, _ in model.reset() }
        .onChange(of: preferences.modelID) { _, _ in model.reset() }
        .onChange(of: preferences.instructions) { _, _ in model.reset() }
        .onChange(of: preferences.reasoning) { _, _ in model.reset() }
        .onChange(of: choices) { _, _ in model.reset() }
        .task(id: catalogRefresh) { await refreshModels() }
        .onDisappear { model.cancel() }
    }

    private var selectedChoice: CodexCleanupModelChoice? { choices.first { $0.id == preferences.modelID } }
    private var reasoningOptions: [CodexCleanupReasoning] {
        var options: [CodexCleanupReasoning] = [.automatic, .modelDefault] + (selectedChoice?.supportedReasoning ?? [])
        if !options.contains(preferences.reasoning) { options.append(preferences.reasoning) }
        return options
    }
    private var configurationIsValid: Bool {
        (try? preferences.resolvedConfiguration(choice: selectedChoice)) != nil
    }
    private var reasoningSummary: String {
        do {
            let config = try preferences.resolvedConfiguration(choice: selectedChoice)
            if let effort = config.reasoningEffort { return "Uses \(effort.label) reasoning. Lower effort can be faster; review cleanup quality." }
            if let effort = selectedChoice?.defaultReasoning { return "Uses model default: \(effort.label)." }
            return "Uses model default; reasoning capabilities are unavailable for this model."
        } catch { return error.localizedDescription }
    }

    private var configurationEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Model")
                TextField("Codex model ID", text: $preferences.modelID)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("codexCleanup.modelID")
                Menu(isLoadingModels ? "Loading models…" : "Choose model") {
                    ForEach(choices) { choice in
                        Button(choice.name) { preferences.modelID = choice.id }
                    }
                }
                .disabled(choices.isEmpty)
                .accessibilityIdentifier("codexCleanup.modelPicker")
                Button("Refresh") { catalogRefresh += 1 }
                    .disabled(isLoadingModels || executable == nil)
                    .accessibilityIdentifier("codexCleanup.refreshModels")
            }
            if let catalogError {
                Text(catalogError).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("codexCleanup.catalogError")
            }
            Text("Saved on this Mac. Choose a catalog model or enter an ID; availability is verified by running cleanup.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Reasoning", selection: $preferences.reasoning) {
                ForEach(reasoningOptions, id: \.self) { effort in
                    Text(effort.label).tag(effort)
                }
            }
            .accessibilityIdentifier("codexCleanup.reasoning")
            Text(reasoningSummary).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("codexCleanup.reasoningSummary")
            Button {
                showsInstructions.toggle()
            } label: {
                Label("Cleanup instructions", systemImage: showsInstructions ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("codexCleanup.toggleInstructions")
            .accessibilityValue(showsInstructions ? "Expanded" : "Collapsed")
            if showsInstructions {
                VStack(alignment: .leading, spacing: 5) {
                    TextEditor(text: $preferences.instructions)
                        .font(.body).padding(4).frame(height: 78)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                        .accessibilityIdentifier("codexCleanup.instructions")
                    HStack {
                        Text("Saved automatically · \(preferences.instructions.utf8.count) / 8,192 bytes")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Restore default") { preferences.instructions = CodexCleanupConfiguration.defaultInstructions }
                            .accessibilityIdentifier("codexCleanup.restoreInstructions")
                    }
                }
            }
            if !configurationIsValid {
                Text("Check the model ID, supported reasoning level, and nonempty instructions within the size limit.")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .disabled(model.isRunning)
    }

    private func timingDetails(_ metrics: CodexCleanupMetrics) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                showsTiming.toggle()
            } label: {
                Label("Timing details", systemImage: showsTiming ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("codexCleanup.toggleTiming")
            .accessibilityValue(showsTiming ? "Expanded" : "Collapsed")
            if showsTiming {
            VStack(alignment: .leading, spacing: 3) {
                Text(metrics.displaySummary).font(.caption).monospacedDigit()
                Text("Codex turn includes connection, waiting and model processing. These are client measurements.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("codexCleanup.timings")
            }
        }
    }

    @MainActor private func refreshModels() async {
        guard !Task.isCancelled else { return }
        let refresh = catalogRefresh
        isLoadingModels = true
        defer { if refresh == catalogRefresh { isLoadingModels = false } }
        catalogError = nil
        if usesTestRunner {
            choices = [.init(id: "gpt-5.5", name: "GPT-5.5", supportedReasoning: [.low, .medium], defaultReasoning: .medium), .init(id: "qa-cleanup-model", name: "QA cleanup model", supportedReasoning: [.low, .medium], defaultReasoning: .medium)]
            return
        }
        guard let executable else { choices = []; return }
        do {
            let loaded = try await CodexCleanupCatalog(executable: executable).load()
            try Task.checkCancellation()
            choices = loaded
        } catch is CancellationError { }
        catch {
            choices = []
            catalogError = CodexCleanupError.catalogUnavailable.localizedDescription
        }
    }

    private func run() {
        do {
            let configuration = try preferences.resolvedConfiguration(choice: selectedChoice)
            let request = groupID == Self.exampleID
                ? CodexCleanupRequest(text: input, terms: CodexCleanupRequest.example.terms, corrections: [])
                : try CodexCleanupRequest.make(text: input, groupID: groupID, state: appState)
            if usesTestRunner {
                model.runMeasured(request) { _ in
                    try await Task.sleep(for: .seconds(2))
                    return CodexCleanupOutput(text: "We put the Supabase credentials in the Vercel environment.",
                                              metrics: .init(preparation: 0.01, startup: 0.1, turn: 1.8, finalization: 0.01,
                                                             total: 1.92, inputTokens: 100, cachedInputTokens: 0, outputTokens: 20))
                }
                return
            }
            guard let executable else { throw CodexCleanupError.missingCodex }
            let service = CodexTextCleanup(executable: executable, configuration: configuration)
            model.runMeasured(request) {
                let output = try await service.cleanWithMetrics($0)
                if let metrics = output.metrics {
                    DiagnosticLog.write("Codex cleanup model=\(configuration.modelID) effort=\(configuration.reasoningEffort?.rawValue ?? "default") \(metrics.diagnosticSummary)")
                }
                return output
            }
        } catch {
            model.error = (error as? CodexCleanupError)?.localizedDescription ?? CodexCleanupError.failed.localizedDescription
        }
    }

    /// Mark the smallest contiguous changed span; linear work even for large or unrelated results.
    static func highlighted(_ output: String, comparedTo original: String) -> AttributedString {
        let old = Array(original), new = Array(output)
        let prefix = zip(old, new).prefix(while: { $0 == $1 }).count
        let suffix = zip(old.dropFirst(prefix).reversed(), new.dropFirst(prefix).reversed())
            .prefix(while: { $0 == $1 }).count
        var result = AttributedString(output)
        let start = result.characters.index(result.startIndex, offsetBy: prefix)
        let end = result.characters.index(result.endIndex, offsetBy: -suffix)
        if start < end { result[start..<end].backgroundColor = .yellow.opacity(0.3) }
        return result
    }
}

extension CodexCleanupRequest {
    @MainActor
    static func make(text: String, groupID: String, state: AppState) throws -> Self {
        guard state.cleanupGroups.contains(where: { $0.id == groupID && $0.isEnabled }) else {
            throw CodexCleanupError.scopeUnavailable
        }
        let snapshot = state.localCorrectionSnapshot
        // Ask the same engine used by dictation to resolve overrides and suppressions.
        // Never send rules from another group, disabled rules, or shadowed global aliases.
        let corrections = snapshot.isEnabled ? snapshot.rules.filter { rule in
            guard rule.enabled, !rule.suppressesGlobal,
                  rule.group == nil || rule.group == groupID else { return false }
            let result = state.previewLocalCorrections(rule.source, activeGroupID: groupID)
            return result.replacementCount > 0 && result.text == rule.replacement
        }.map { Correction(source: $0.source, replacement: $0.replacement) } : []
        return Self(text: text, terms: state.preferredTerms(for: groupID), corrections: corrections)
    }

}
