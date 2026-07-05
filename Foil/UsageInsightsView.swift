import SwiftUI

struct UsageInsightsView: View {
    @Bindable var appState: AppState
    let usageEventStore: UsageEventStore
    @State private var refreshCounter = 0

    private var summary: UsageSummary {
        _ = refreshCounter
        return usageEventStore.summary()
    }

    private var trend: [UsageTrendBucket] {
        _ = refreshCounter
        return Array(usageEventStore.dailyTrend().suffix(7))
    }

    private var topApps: [UsageTopApp] {
        _ = refreshCounter
        return usageEventStore.topApps(limit: 5)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                controls

                if !appState.usageMetricsEnabled {
                    disabledBanner
                }

                if summary.totalSessions == 0 {
                    emptyState
                } else {
                    summaryGrid
                    trendSection
                    topAppsSection
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FoilTheme.windowBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("usageInsights.root")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Insights")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(FoilTheme.deepTeal)
            Text("Local usage metrics from dictation sessions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("usageInsights.subtitle")
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Toggle("Usage metrics", isOn: usageMetricsBinding)
                .toggleStyle(.switch)
                .accessibilityIdentifier("usageInsights.metricsToggle")

            Button("Delete Usage Metrics", action: deleteUsageMetrics)
                .disabled(summary.totalSessions == 0)
                .foregroundStyle(.red)
                .accessibilityIdentifier("usageInsights.deleteButton")

            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FoilTheme.separator, lineWidth: 1)
        }
    }

    private var disabledBanner: some View {
        Label {
            Text("Future usage metrics are paused. Retained usage metrics stay here until you delete them.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "pause.circle.fill")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("usageInsights.disabledState")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No usage metrics yet")
                .font(.headline)
            Text("Start dictating with usage metrics enabled to see words, sessions, trends, and top apps.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FoilTheme.separator, lineWidth: 1)
        }
        .accessibilityIdentifier("usageInsights.emptyState")
    }

    private var summaryGrid: some View {
        HStack(spacing: 12) {
            metricTile(title: "Total words", value: summary.totalWords.formatted(), identifier: "usageInsights.totalWords")
            metricTile(title: "Sessions", value: summary.totalSessions.formatted(), identifier: "usageInsights.totalSessions")
            metricTile(title: "Time saved", value: formattedTimeSaved, identifier: "usageInsights.timeSaved")
        }
        .accessibilityIdentifier("usageInsights.summary")
    }

    private func metricTile(title: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FoilTheme.separator, lineWidth: 1)
        }
        .accessibilityIdentifier(identifier)
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily Trend")
                .font(.headline)
            VStack(spacing: 8) {
                ForEach(trend, id: \.startDate) { bucket in
                    HStack(spacing: 12) {
                        Text(Self.shortDateFormatter.string(from: bucket.startDate))
                            .frame(width: 76, alignment: .leading)
                            .foregroundStyle(.secondary)
                        ProgressView(value: Double(bucket.wordCount), total: Double(maxTrendWords))
                            .frame(maxWidth: .infinity)
                        Text("\(bucket.wordCount.formatted()) words")
                            .monospacedDigit()
                            .frame(width: 92, alignment: .trailing)
                        Text("\(bucket.sessionCount) sessions")
                            .monospacedDigit()
                            .frame(width: 78, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .accessibilityIdentifier("usageInsights.trend.\(Self.isoDayFormatter.string(from: bucket.startDate))")
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FoilTheme.separator, lineWidth: 1)
        }
        .accessibilityIdentifier("usageInsights.trend")
    }

    private var topAppsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top Apps")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(topApps, id: \.displayName) { app in
                    HStack {
                        Text(app.displayName)
                            .font(.subheadline.weight(.medium))
                            .accessibilityIdentifier("usageInsights.topApp.\(Self.accessibilityKey(for: app.displayName))")
                        Spacer()
                        Text("\(app.wordCount.formatted()) words")
                            .monospacedDigit()
                        Text("\(app.sessionCount) sessions")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 82, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FoilTheme.separator, lineWidth: 1)
        }
        .accessibilityIdentifier("usageInsights.topApps")
    }

    private var usageMetricsBinding: Binding<Bool> {
        Binding(
            get: { appState.usageMetricsEnabled },
            set: { enabled in
                appState.usageMetricsEnabled = enabled
                usageEventStore.isEnabled = enabled
                refreshCounter += 1
            }
        )
    }

    private func deleteUsageMetrics() {
        _ = usageEventStore.deleteAll()
        refreshCounter += 1
    }

    private var formattedTimeSaved: String {
        let minutes = max(0, summary.estimatedTimeSavedSeconds) / 60
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours) hr" : "\(hours) hr \(remainingMinutes) min"
    }

    private var maxTrendWords: Int {
        max(1, trend.map(\.wordCount).max() ?? 1)
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let isoDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func accessibilityKey(for value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(scalars).lowercased()
    }
}
