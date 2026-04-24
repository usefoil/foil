import SwiftUI

struct HistoryPopoverView: View {
    var history: TranscriptionHistory
    var onRetry: ((TranscriptionRecord) -> Void)?
    @State private var searchText = ""

    private var filteredRecords: [TranscriptionRecord] {
        if searchText.isEmpty { return history.records }
        return history.records.filter { record in
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
            searchField
            Divider()
            if filteredRecords.isEmpty {
                emptyState
            } else {
                recordsList
            }
        }
        .frame(width: 350, height: 400)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search transcriptions...", text: $searchText)
                .textFieldStyle(.plain)
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
        .padding(8)
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text(searchText.isEmpty ? "No transcriptions yet" : "No matches")
                .foregroundStyle(.secondary)
            Spacer()
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
        HStack(alignment: .top, spacing: 8) {
            if record.isFailure {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(record.text ?? record.error ?? "")
                    .lineLimit(2)
                    .font(.body)
                    .foregroundStyle(record.isFailure ? .red : .primary)
                Text(record.relativeTimestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let text = record.text {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }

            if record.isFailure, record.audioFileURL != nil {
                Button {
                    onRetry?(record)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Retry transcription")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
