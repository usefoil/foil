import SwiftUI
import AppKit

struct CodexCleanupView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var model = CodexCleanupModel()
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
            Text("Codex runs on this Mac and sends your entered text and selected Vocabulary to OpenAI’s hosted model. Each click runs one cleanup; it does not enable cleanup for recordings.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("codexCleanup.disclosure")
            HStack {
                Label(!hasRunner ? "Codex CLI not found" : "Codex CLI found · \(CodexTextCleanup.defaultModel)",
                      systemImage: !hasRunner ? "exclamationmark.circle" : "checkmark.circle")
                    .accessibilityIdentifier("codexCleanup.connection")
                Spacer()
                Button("Check again") { executable = CodexTextCleanup.findExecutable() }
            }
            Text("Uses your Codex CLI sign-in. Model access is checked when you run cleanup.")
                .font(.caption).foregroundStyle(.secondary)
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
                            .accessibilityIdentifier("codexCleanup.result")
                    }
                    .background(.background)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    Text(model.result == nil ? "Review the result before using it." : "Highlighted area contains changes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 170)
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
                                  || input.utf8.count > CodexCleanupRequest.maximumTextBytes)
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
            Text("This experiment does not save text to Foil History or change Vocabulary. Closing this panel discards the example. Recording and audio are not used.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 740, height: 610)
        .onChange(of: input) { _, _ in model.reset() }
        .onChange(of: groupID) { _, _ in model.reset() }
        .onDisappear { model.cancel() }
    }

    private func run() {
        if usesTestRunner {
            model.run(.example) { _ in
                try await Task.sleep(for: .seconds(2))
                return "We put the Supabase credentials in the Vercel environment."
            }
            return
        }
        guard let executable else { return }
        do {
            let request = groupID == Self.exampleID
                ? CodexCleanupRequest(text: input, terms: CodexCleanupRequest.example.terms, corrections: [])
                : try CodexCleanupRequest.make(text: input, groupID: groupID, state: appState)
            let service = CodexTextCleanup(executable: executable)
            model.run(request) { try await service.clean($0) }
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
