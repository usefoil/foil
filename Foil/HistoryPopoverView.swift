import AppKit
import SwiftUI

enum HistoryVocabularyRecleanResult: Equatable {
    case updated
    case saveRejected
    case cleanupUnavailable
    case cleanupFailed
}

struct HistoryPopoverView: View {
    enum Filter: String, CaseIterable {
        case all = "All"
        case successful = "Successful"
        case failed = "Failed"
    }

    var history: TranscriptionHistory
    var onRetry: ((TranscriptionRecord) -> Void)?
    var onPaste: ((String) -> Void)?
    var onSaveVocabularyCorrection: ((String, String, String?, UUID?, String?) -> VocabularyCorrection?)?
    var onSaveAndRecleanVocabularyCorrection: ((String, String, String?, UUID, String?) async -> HistoryVocabularyRecleanResult)?
    var canSaveAndRecleanVocabularyCorrection = false
    var showsHeader = true

    private struct VocabularyCorrectionDraft: Identifiable {
        let id = UUID()
        let recordID: UUID
        let writtenAs: String
        let sourceAppName: String?
    }

    private struct VocabularyToken: Identifiable {
        let id: Int
        let text: String
        let correctionText: String
    }

    private struct VocabularyTokenSelection: Equatable {
        let recordID: UUID
        var lowerTokenID: Int
        var upperTokenID: Int

        init(recordID: UUID, tokenID: Int) {
            self.recordID = recordID
            self.lowerTokenID = tokenID
            self.upperTokenID = tokenID
        }

        var range: ClosedRange<Int> {
            lowerTokenID...upperTokenID
        }
    }

    private struct VocabularyCorrectionSheet: View {
        let draft: VocabularyCorrectionDraft
        let canShowSaveAndReclean: Bool
        let onCancel: () -> Void
        let onSaveVocabularyCorrection: ((String, String, String?, UUID?, String?) -> VocabularyCorrection?)?
        let onSaveAndRecleanVocabularyCorrection: ((String, String, String?, UUID, String?) async -> HistoryVocabularyRecleanResult)?
        let onRecleanUpdated: () -> Void

        @State private var writtenAs: String
        @State private var correctVersion = ""
        @State private var note = ""
        @State private var saveError: String?
        @State private var isSavingAndRecleaning = false

        init(
            draft: VocabularyCorrectionDraft,
            canShowSaveAndReclean: Bool,
            onCancel: @escaping () -> Void,
            onSaveVocabularyCorrection: ((String, String, String?, UUID?, String?) -> VocabularyCorrection?)?,
            onSaveAndRecleanVocabularyCorrection: ((String, String, String?, UUID, String?) async -> HistoryVocabularyRecleanResult)?,
            onRecleanUpdated: @escaping () -> Void
        ) {
            self.draft = draft
            self.canShowSaveAndReclean = canShowSaveAndReclean
            self.onCancel = onCancel
            self.onSaveVocabularyCorrection = onSaveVocabularyCorrection
            self.onSaveAndRecleanVocabularyCorrection = onSaveAndRecleanVocabularyCorrection
            self.onRecleanUpdated = onRecleanUpdated
            _writtenAs = State(initialValue: draft.writtenAs)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Add to Vocabulary")
                        .font(.headline)
                    Spacer()
                    Button("Cancel") {
                        isSavingAndRecleaning = false
                        onCancel()
                    }
                    .accessibilityIdentifier("history.vocabulary.cancelButton")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Foil wrote")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Phrase Foil wrote", text: $writtenAs, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("history.vocabulary.writtenAsField")
                        .accessibilityValue(writtenAs)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Use this instead")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Correct version", text: $correctVersion)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("history.vocabulary.correctVersionField")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Optional context", text: $note)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("history.vocabulary.noteField")
                }

                if let saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("history.vocabulary.error")
                }

                HStack {
                    Spacer()
                    Button {
                        guard let onSaveVocabularyCorrection else { return }
                        let savedCorrection = onSaveVocabularyCorrection(
                            writtenAs,
                            correctVersion,
                            note,
                            draft.recordID,
                            draft.sourceAppName
                        )
                        if savedCorrection == nil {
                            saveError = "Add both the phrase Foil wrote and the corrected version."
                        } else {
                            onCancel()
                        }
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .disabled(onSaveVocabularyCorrection == nil || isFormIncomplete)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("history.vocabulary.saveButton")

                    if canShowSaveAndReclean {
                        Button {
                            Task {
                                await saveAndReclean()
                            }
                        } label: {
                            if isSavingAndRecleaning {
                                Label("Re-cleaning", systemImage: "wand.and.stars")
                            } else {
                                Label("Save and Re-clean", systemImage: "wand.and.stars")
                            }
                        }
                        .disabled(isSavingAndRecleaning || isFormIncomplete)
                        .accessibilityIdentifier("history.vocabulary.saveAndRecleanButton")
                    }
                }
            }
            .padding(18)
            .frame(width: 460)
        }

        private var isFormIncomplete: Bool {
            writtenAs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                correctVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        private func saveAndReclean() async {
            guard let onSaveAndRecleanVocabularyCorrection else { return }
            isSavingAndRecleaning = true
            saveError = nil
            let result = await onSaveAndRecleanVocabularyCorrection(
                writtenAs,
                correctVersion,
                note,
                draft.recordID,
                draft.sourceAppName
            )
            isSavingAndRecleaning = false

            switch result {
            case .updated:
                onRecleanUpdated()
            case .saveRejected:
                saveError = "Add both the phrase Foil wrote and the corrected version."
            case .cleanupUnavailable:
                saveError = "Turn on transcript cleanup and choose a cleanup provider to re-clean this transcript."
            case .cleanupFailed:
                saveError = "Could not re-clean this transcript. The History item was left unchanged."
            }
        }
    }

    @State private var searchText = ""
    @State private var filter: Filter = .all
    @State private var sourceAppFilter: String?
    @State private var isShowingClearConfirmation = false
    @State private var isShowingDeleteOlderConfirmation = false
    @State private var isShowingDeleteFilteredConfirmation = false
    @State private var deleteOlderDays: Int = 7
    @State private var pendingDeleteRecord: TranscriptionRecord?
    @State private var pendingDetailDeleteRecord: TranscriptionRecord?
    @State private var selectedRecord: TranscriptionRecord?
    @State private var editedText = ""
    @State private var vocabularyDraft: VocabularyCorrectionDraft?
    @State private var vocabularySelection: VocabularyTokenSelection?

    private var filteredRecords: [TranscriptionRecord] {
        history.records.filter { record in
            let matchesFilter = switch filter {
            case .all: true
            case .successful: !record.isFailure
            case .failed: record.isFailure
            }
            guard matchesFilter else { return false }

            if let sourceAppFilter, record.sourceAppName != sourceAppFilter {
                return false
            }

            if searchText.isEmpty { return true }
            if let text = record.text {
                return text.localizedCaseInsensitiveContains(searchText)
            }
            if let error = record.error {
                return error.localizedCaseInsensitiveContains(searchText)
            }
            return false
        }
    }

    private var sourceAppFilters: [String] {
        let names = history.records.compactMap { record -> String? in
            let trimmed = record.sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        return Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
                Divider()
            }
            searchAndFilters
            Divider()
            if filteredRecords.isEmpty {
                emptyState
            } else {
                recordsList
            }
        }
        .accessibilityIdentifier("history.root")
        .frame(minWidth: 420, idealWidth: 560, minHeight: 420, idealHeight: 560)
        .alert("Clear History?", isPresented: $isShowingClearConfirmation) {
            Button("Clear History", role: .destructive) {
                history.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all stored transcripts and any retained failed-audio retry files from this Mac.")
        }
        .alert("Delete History Item?", isPresented: pendingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let pendingDeleteRecord {
                    history.delete(id: pendingDeleteRecord.id)
                    if selectedRecord?.id == pendingDeleteRecord.id {
                        selectedRecord = nil
                    }
                }
                pendingDeleteRecord = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteRecord = nil
            }
        } message: {
            Text("This removes the selected transcript and any retained failed-audio retry file from this Mac.")
        }
        .alert("Delete Old Records?", isPresented: $isShowingDeleteOlderConfirmation) {
            Button("Delete", role: .destructive) {
                let cutoff = Calendar.current.date(byAdding: .day, value: -deleteOlderDays, to: Date()) ?? Date()
                history.deleteOlderThan(cutoff)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all transcriptions older than \(deleteOlderDays) days.")
        }
        .alert("Delete Filtered History?", isPresented: $isShowingDeleteFilteredConfirmation) {
            Button("Delete Filtered", role: .destructive) {
                history.deleteFiltered(filteredRecords)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the currently visible filtered transcripts and any retained failed-audio retry files from this Mac.")
        }
        .sheet(item: $selectedRecord) { record in
            detailView(for: history.records.first { $0.id == record.id } ?? record)
        }
        .sheet(item: $vocabularyDraft) { draft in
            vocabularyCorrectionSheet(for: draft)
        }
        .onReceive(NotificationCenter.default.publisher(for: .foilHistoryUITestCommandRelay)) { notification in
            guard let command = HistoryUITestCommand(notification: notification) else { return }
            handleUITestHistoryCommand(command)
        }
    }

    private var pendingDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { pendingDeleteRecord != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteRecord = nil
                }
            }
        )
    }

    private func handleUITestHistoryCommand(_ command: HistoryUITestCommand) {
        switch command.name {
        case "search":
            searchText = command.query ?? ""
        case "filter":
            if let value = command.filter,
               let nextFilter = Filter(rawValue: value) {
                filter = nextFilter
            }
        case "appFilter":
            if let appName = command.appName, sourceAppFilters.contains(appName) {
                sourceAppFilter = appName
            } else {
                sourceAppFilter = nil
            }
        case "showDeleteFirst":
            pendingDeleteRecord = filteredRecords.first
        case "cancelDeleteFirst":
            pendingDeleteRecord = nil
        case "selectDetail":
            guard filteredRecords.indices.contains(command.index) else { return }
            let record = filteredRecords[command.index]
            selectedRecord = record
            editedText = record.text ?? ""
        case "showDetailDelete":
            pendingDetailDeleteRecord = selectedRecord
        case "cancelDetailDelete":
            pendingDetailDeleteRecord = nil
        case "dismissDetail":
            selectedRecord = nil
        case "showDeleteFiltered":
            isShowingDeleteFilteredConfirmation = true
        case "cancelDeleteFiltered":
            isShowingDeleteFilteredConfirmation = false
        case "showClear":
            isShowingClearConfirmation = true
        case "clear":
            isShowingClearConfirmation = false
            history.clear()
        default:
            break
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("History")
                    .font(.headline)
                Text(history.isPersistenceEnabled ? "\(history.records.count) of \(history.retentionLimit) stored" : "History storage off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                copy(history.exportMarkdown())
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("history.exportButton")
            .disabled(history.records.isEmpty)

            Button("Clear", role: .destructive) {
                isShowingClearConfirmation = true
            }
            .accessibilityIdentifier("history.clearButton")
            .disabled(history.records.isEmpty)

            Menu {
                Button("Delete Older Than 7 Days") {
                    deleteOlderDays = 7
                    isShowingDeleteOlderConfirmation = true
                }
                Button("Delete Older Than 30 Days") {
                    deleteOlderDays = 30
                    isShowingDeleteOlderConfirmation = true
                }
                Divider()
                Button("Delete All Filtered", role: .destructive) {
                    isShowingDeleteFilteredConfirmation = true
                }
                .disabled(filteredRecords.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityIdentifier("history.moreMenu")
            .accessibilityLabel("More actions")
        }
        .padding(12)
        .accessibilityIdentifier("history.header")
    }

    private var searchAndFilters: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcriptions...", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("history.searchField")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                ForEach(Filter.allCases, id: \.self) { filter in
                    Button(filter.rawValue) {
                        self.filter = filter
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityAddTraits(self.filter == filter ? .isSelected : [])
                    .accessibilityValue(self.filter == filter ? "Selected" : "Not selected")
                }
            }
            .accessibilityIdentifier("history.filterPicker")

            if !sourceAppFilters.isEmpty {
                HStack {
                    Button("All apps") {
                        sourceAppFilter = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("history.appFilter.allApps")
                    .accessibilityAddTraits(sourceAppFilter == nil ? .isSelected : [])
                    .accessibilityValue(sourceAppFilter == nil ? "Selected" : "Not selected")

                    ForEach(sourceAppFilters, id: \.self) { appName in
                        Button(appName) {
                            sourceAppFilter = appName
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("history.appFilter.\(appName)")
                        .accessibilityAddTraits(sourceAppFilter == appName ? .isSelected : [])
                        .accessibilityValue(sourceAppFilter == appName ? "Selected" : "Not selected")
                    }
                }
                .accessibilityIdentifier("history.appFilterPicker")
            }
        }
        .padding(10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: emptyStateImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(emptyStateTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("history.emptyState.title")
            Text(emptyStateDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .accessibilityIdentifier("history.emptyState.detail")
            Spacer()
        }
        .accessibilityLabel("\(emptyStateTitle). \(emptyStateDetail)")
        .accessibilityIdentifier("history.emptyState")
    }

    private var emptyStateImage: String {
        if !history.isPersistenceEnabled { return "clock.badge.xmark" }
        if !searchText.isEmpty { return "magnifyingglass" }
        switch filter {
        case .all:
            return "clock"
        case .successful:
            return "text.bubble"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var emptyStateTitle: String {
        if !history.isPersistenceEnabled { return "History storage is off" }
        if !searchText.isEmpty || sourceAppFilter != nil { return "No matches" }
        switch filter {
        case .all:
            return "No transcriptions yet"
        case .successful:
            return "No successful transcriptions"
        case .failed:
            return "No failed transcriptions"
        }
    }

    private var emptyStateDetail: String {
        if !history.isPersistenceEnabled {
            return "Turn on history retention in Settings to keep future transcripts here."
        }
        if !searchText.isEmpty || sourceAppFilter != nil {
            return "Clear the search or change the filter to see more history."
        }
        switch filter {
        case .all:
            return "Record with your hotkey or the Start button, then completed transcripts will appear here."
        case .successful:
            return "Successful transcripts will appear here after recording and transcription finish."
        case .failed:
            return "Retryable failures appear here with their retained audio when transcription fails."
        }
    }

    private var recordsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredRecords) { record in
                    recordRow(record)
                    Divider()
                }
            }
        }
    }

    private func recordRow(_ record: TranscriptionRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: record.isFailure ? "exclamationmark.triangle.fill" : "text.bubble")
                .foregroundStyle(record.isFailure ? .red : .secondary)
                .font(.caption)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                transcriptSummary(for: record)
                HStack(spacing: 5) {
                    Text(record.relativeTimestamp)
                    if let sourceAppName = record.sourceAppName {
                        Text("·")
                        Text(sourceAppName)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Button {
                    selectedRecord = record
                    editedText = record.text ?? ""
                } label: {
                    Label("Details", systemImage: "info.circle")
                }
                .accessibilityIdentifier("history.row.detailsButton")
                .buttonStyle(.borderless)
                .controlSize(.small)
                .frame(minHeight: 18)
            }

            Spacer()

            rowActions(for: record)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.row")
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func transcriptSummary(for record: TranscriptionRecord) -> some View {
        if let text = record.text {
            VStack(alignment: .leading, spacing: 5) {
                WrappingHStack(horizontalSpacing: 3, verticalSpacing: 3) {
                    ForEach(vocabularyTokens(from: text)) { token in
                        vocabularyTokenButton(record: record, token: token)
                    }

                    if transcriptNeedsEllipsis(text) {
                        Text("...")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                if let selectedText = selectedVocabularyText(for: record, tokens: vocabularyTokens(from: text)) {
                    HStack(spacing: 8) {
                        Text(selectedText)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("history.vocabulary.selectedText")

                        Button {
                            beginVocabularyCorrection(for: record, writtenAs: selectedText)
                        } label: {
                            Label("Add selected", systemImage: "text.badge.plus")
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("history.vocabulary.addSelectionButton")

                        Button {
                            clearVocabularySelection()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.plain)
                        .controlSize(.small)
                        .help("Clear Vocabulary selection")
                        .accessibilityLabel("Clear Vocabulary selection")
                        .accessibilityIdentifier("history.vocabulary.clearSelectionButton")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(record.error ?? "")
                .lineLimit(3)
                .font(.body)
                .textSelection(.enabled)
                .foregroundStyle(.red)
        }
    }

    private func vocabularyTokenButton(record: TranscriptionRecord, token: VocabularyToken) -> some View {
        let isSelected = isVocabularyTokenSelected(record: record, token: token)
        return Button {
            selectVocabularyToken(record: record, token: token)
        } label: {
            Text(token.text)
                .font(.body)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(
                    isSelected ? Color.accentColor.opacity(0.16) : Color.yellow.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help("Select \(token.correctionText) for Vocabulary")
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("history.row.transcriptVocabularyToken")
        .accessibilityLabel("\(isSelected ? "Selected" : "Select") \(token.correctionText) for Vocabulary")
    }

    @ViewBuilder
    private func rowActions(for record: TranscriptionRecord) -> some View {
        HStack(spacing: 8) {
            if let text = record.text {
                Button {
                    copy(text)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Copy")
                .accessibilityIdentifier("history.row.copyButton")
                .help("Copy")
                .frame(minWidth: 24, minHeight: 18)

                Button {
                    onPaste?(text)
                } label: {
                    Image(systemName: "arrow.turn.down.left")
                }
                .accessibilityLabel("Paste Again")
                .accessibilityIdentifier("history.row.pasteAgainButton")
                .help("Paste Again")
                .frame(minWidth: 24, minHeight: 18)
            }

            if record.isFailure, record.audioFileURL != nil {
                Button {
                    onRetry?(record)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Retry")
                .accessibilityIdentifier("history.row.retryButton")
                .help("Retry")
                .frame(minWidth: 24, minHeight: 18)
            }

            Button(role: .destructive) {
                pendingDeleteRecord = record
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete")
            .accessibilityIdentifier("history.row.deleteButton")
            .help("Delete")
            .frame(minWidth: 24, minHeight: 18)
        }
        .buttonStyle(.borderless)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func detailView(for record: TranscriptionRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(record.isFailure ? "Failure" : "Transcript")
                    .font(.headline)
                Spacer()
                Text(record.relativeTimestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let text = record.text {
                TextEditor(text: $editedText)
                    .font(.body)
                    .frame(minHeight: 180)
                    .accessibilityIdentifier("history.detail.editor")

                HStack {
                    Button {
                        history.updateSuccess(id: record.id, text: editedText)
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .accessibilityIdentifier("history.detail.saveButton")
                    .frame(minHeight: 18)

                    Button {
                        copy(editedText)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .accessibilityIdentifier("history.detail.copyButton")
                    .frame(minHeight: 18)

                    Button {
                        onPaste?(editedText)
                    } label: {
                        Label("Paste", systemImage: "arrow.turn.down.left")
                    }
                    .accessibilityIdentifier("history.detail.pasteButton")
                    .frame(minHeight: 18)

                    Spacer()

                    Button("Revert") {
                        editedText = text
                    }
                    .frame(minHeight: 18)
                }
                .buttonStyle(.borderless)
            } else {
                Text(record.error ?? "")
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("history.detail.error")

                if record.audioFileURL != nil {
                    Button {
                        onRetry?(record)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("history.detail.retryButton")
                    .frame(minHeight: 18)
                }
            }

            Divider()

            if pendingDetailDeleteRecord?.id == record.id {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Delete this history item?")
                        .font(.callout.weight(.semibold))
                    Text("This removes the selected transcript and any retained failed-audio retry file from this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Confirm Delete", role: .destructive) {
                            history.delete(id: record.id)
                            pendingDetailDeleteRecord = nil
                            selectedRecord = nil
                        }
                        .accessibilityIdentifier("history.detail.confirmDeleteButton")

                        Button("Cancel") {
                            pendingDetailDeleteRecord = nil
                        }
                        .accessibilityIdentifier("history.detail.cancelDeleteButton")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(10)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("history.detail.deleteConfirmation")
            }

            HStack {
                Button(role: .destructive) {
                    pendingDetailDeleteRecord = record
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityIdentifier("history.detail.deleteButton")
                .frame(minHeight: 18)

                Spacer()

                Button("Done") {
                    selectedRecord = nil
                }
                .accessibilityIdentifier("history.detail.doneButton")
                .frame(minHeight: 18)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 520)
        .frame(minHeight: 320)
        .onAppear {
            editedText = record.text ?? ""
        }
    }

    private func beginVocabularyCorrection(for record: TranscriptionRecord, writtenAs: String) {
        let normalizedWrittenAs = writtenAs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedWrittenAs.isEmpty else { return }

        vocabularyDraft = VocabularyCorrectionDraft(
            recordID: record.id,
            writtenAs: normalizedWrittenAs,
            sourceAppName: record.sourceAppName
        )
    }

    private func selectVocabularyToken(record: TranscriptionRecord, token: VocabularyToken) {
        guard var selection = vocabularySelection, selection.recordID == record.id else {
            vocabularySelection = VocabularyTokenSelection(recordID: record.id, tokenID: token.id)
            return
        }

        if token.id < selection.lowerTokenID {
            selection.lowerTokenID = token.id
        } else if token.id > selection.upperTokenID {
            selection.upperTokenID = token.id
        } else if selection.lowerTokenID == selection.upperTokenID {
            clearVocabularySelection()
            return
        } else {
            selection = VocabularyTokenSelection(recordID: record.id, tokenID: token.id)
        }

        vocabularySelection = selection
    }

    private func clearVocabularySelection() {
        vocabularySelection = nil
    }

    private func isVocabularyTokenSelected(record: TranscriptionRecord, token: VocabularyToken) -> Bool {
        guard let selection = vocabularySelection, selection.recordID == record.id else { return false }
        return selection.range.contains(token.id)
    }

    private func selectedVocabularyText(for record: TranscriptionRecord, tokens: [VocabularyToken]) -> String? {
        guard let selection = vocabularySelection, selection.recordID == record.id else { return nil }
        let selectedTokens = tokens.filter { selection.range.contains($0.id) }
        guard !selectedTokens.isEmpty else { return nil }
        return selectedTokens.map(\.correctionText).joined(separator: " ")
    }

    private func vocabularyCorrectionSheet(for draft: VocabularyCorrectionDraft) -> some View {
        VocabularyCorrectionSheet(
            draft: draft,
            canShowSaveAndReclean: canShowSaveAndReclean,
            onCancel: { vocabularyDraft = nil },
            onSaveVocabularyCorrection: onSaveVocabularyCorrection,
            onSaveAndRecleanVocabularyCorrection: onSaveAndRecleanVocabularyCorrection,
            onRecleanUpdated: {
                clearVocabularySelection()
                vocabularyDraft = nil
            }
        )
    }

    private var canShowSaveAndReclean: Bool {
        onSaveAndRecleanVocabularyCorrection != nil && canSaveAndRecleanVocabularyCorrection
    }

    private func vocabularyTokens(from text: String) -> [VocabularyToken] {
        text.split(whereSeparator: \.isWhitespace)
            .prefix(28)
            .enumerated()
            .compactMap { index, rawToken in
                let displayText = String(rawToken)
                let correctionText = displayText.trimmingCharacters(in: .punctuationCharacters)
                guard !correctionText.isEmpty else { return nil }
                return VocabularyToken(id: index, text: displayText, correctionText: correctionText)
            }
    }

    private func transcriptNeedsEllipsis(_ text: String) -> Bool {
        text.split(whereSeparator: \.isWhitespace).count > 28
    }
}

private struct WrappingHStack: Layout {
    var horizontalSpacing: CGFloat = 4
    var verticalSpacing: CGFloat = 4

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .greatestFiniteMagnitude)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.enumerated().reduce(CGFloat.zero) { partial, item in
            partial + item.element.height + (item.offset == 0 ? 0 : verticalSpacing)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        let constrainedWidth = maxWidth.isFinite ? maxWidth : .greatestFiniteMagnitude

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = current.items.isEmpty ? size.width : current.width + horizontalSpacing + size.width

            if !current.items.isEmpty, nextWidth > constrainedWidth {
                rows.append(current)
                current = Row()
            }

            current.items.append(Item(index: index, size: size))
            current.width = current.items.count == 1 ? size.width : current.width + horizontalSpacing + size.width
            current.height = max(current.height, size.height)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }

        return rows
    }
}
