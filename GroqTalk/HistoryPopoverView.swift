import AppKit
import SwiftUI

struct HistoryPopoverView: View {
    enum Filter: String, CaseIterable {
        case all = "All"
        case successful = "Successful"
        case failed = "Failed"
    }

    var history: TranscriptionHistory
    var onRetry: ((TranscriptionRecord) -> Void)?
    var onPaste: ((String) -> Void)?
    var showsHeader = true

    @State private var searchText = ""
    @State private var filter: Filter = .all
    @State private var isShowingClearConfirmation = false
    @State private var isShowingDeleteOlderConfirmation = false
    @State private var isShowingDeleteFilteredConfirmation = false
    @State private var deleteOlderDays: Int = 7
    @State private var pendingDeleteRecord: TranscriptionRecord?
    @State private var pendingDetailDeleteRecord: TranscriptionRecord?
    @State private var selectedRecord: TranscriptionRecord?
    @State private var editedText = ""

    private var filteredRecords: [TranscriptionRecord] {
        history.records.filter { record in
            let matchesFilter = switch filter {
            case .all: true
            case .successful: !record.isFailure
            case .failed: record.isFailure
            }
            guard matchesFilter else { return false }

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
        .onReceive(DistributedNotificationCenter.default().publisher(for: UITestingController.historyCommandNotification)) { notification in
            guard isUITesting else { return }
            handleUITestHistoryCommand(notification)
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

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    private func handleUITestHistoryCommand(_ notification: Notification) {
        guard let command = notification.userInfo?["command"] as? String else { return }

        switch command {
        case "search":
            searchText = notification.userInfo?["query"] as? String ?? ""
        case "filter":
            if let value = notification.userInfo?["filter"] as? String,
               let nextFilter = Filter(rawValue: value) {
                filter = nextFilter
            }
        case "showDeleteFirst":
            pendingDeleteRecord = filteredRecords.first
        case "cancelDeleteFirst":
            pendingDeleteRecord = nil
        case "selectDetail":
            let index = notification.userInfo?["index"] as? Int ?? 0
            guard filteredRecords.indices.contains(index) else { return }
            let record = filteredRecords[index]
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
        if !searchText.isEmpty { return "No matches" }
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
        if !searchText.isEmpty {
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
                Text(record.text ?? record.error ?? "")
                    .lineLimit(3)
                    .font(.body)
                    .textSelection(.enabled)
                    .foregroundStyle(record.isFailure ? .red : .primary)
                Text(record.relativeTimestamp)
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
        .onTapGesture {
            selectedRecord = record
            editedText = record.text ?? ""
        }
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
}
