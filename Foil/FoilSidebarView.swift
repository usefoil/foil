import SwiftUI

enum FoilAppSection: String, Hashable, CaseIterable {
    case home
    case insights
    case history
    case general
    case recording
    case transcription
    case cleanup
    case paste
    case storage
    case whatsNew
    case experimental

    var title: String {
        switch self {
        case .home: "Home"
        case .insights: "Insights"
        case .history: "History"
        case .general: "General"
        case .recording: "Recording"
        case .transcription: "Transcription"
        case .cleanup: "Cleanup"
        case .paste: "Paste"
        case .storage: "Storage"
        case .whatsNew: "What's New"
        case .experimental: "Experimental"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .insights: "chart.bar.xaxis"
        case .history: "clock"
        case .general: "gearshape"
        case .recording: "mic"
        case .transcription: "waveform"
        case .cleanup: "wand.and.stars"
        case .paste: "text.cursor"
        case .storage: "lock"
        case .whatsNew: "sparkles"
        case .experimental: "testtube.2"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .home: "appShell.nav.home"
        case .insights: "appShell.nav.insights"
        case .history: "appShell.nav.history"
        case .general: "appShell.nav.settings.general"
        case .recording: "appShell.nav.settings.recording"
        case .transcription: "appShell.nav.settings.transcription"
        case .cleanup: "appShell.nav.settings.cleanup"
        case .paste: "appShell.nav.settings.paste"
        case .storage: "appShell.nav.settings.storage"
        case .whatsNew: "appShell.nav.settings.whatsNew"
        case .experimental: "appShell.nav.settings.experimental"
        }
    }

    static let workspace: [FoilAppSection] = [.home, .insights, .history]
    static let preferences: [FoilAppSection] = [.general, .recording, .transcription, .cleanup, .paste, .storage, .whatsNew, .experimental]

    private static let pendingSelectionKey = "FoilAppShell.pendingSelection"
    static let selectionRequestedNotification = Notification.Name("FoilAppShell.selectionRequested")

    static func request(_ section: FoilAppSection) {
        UserDefaults.standard.set(section.rawValue, forKey: pendingSelectionKey)
        NotificationCenter.default.post(
            name: selectionRequestedNotification,
            object: nil,
            userInfo: ["section": section.rawValue]
        )
    }

    static func takePendingRequest() -> FoilAppSection? {
        let defaults = UserDefaults.standard
        guard let rawValue = defaults.string(forKey: pendingSelectionKey) else {
            return nil
        }
        defaults.removeObject(forKey: pendingSelectionKey)
        return FoilAppSection(rawValue: rawValue)
    }
}

struct FoilSidebarView: View {
    @Binding var selection: FoilAppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            brandHeader
            sidebarGroup(title: "Workspace", sections: FoilAppSection.workspace)
            sidebarGroup(title: "Preferences", sections: FoilAppSection.preferences)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(width: 220, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(FoilTheme.sidebarBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("appShell.sidebar")
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            FoilCylinderMark(size: 30)
            Text(AppBrand.name)
                .font(.headline.weight(.semibold))
                .foregroundStyle(FoilTheme.deepTeal)
        }
        .padding(.horizontal, 6)
    }

    private func sidebarGroup(title: String, sections: [FoilAppSection]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            ForEach(sections, id: \.self) { section in
                sidebarButton(section)
            }
        }
    }

    private func sidebarButton(_ section: FoilAppSection) -> some View {
        Button {
            selection = section
        } label: {
            Label(section.title, systemImage: section.systemImage)
                .font(.system(size: 13, weight: selection == section ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .foregroundStyle(selection == section ? FoilTheme.deepTeal : .primary)
                .background {
                    if selection == section {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(FoilTheme.deepTeal.opacity(0.11))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(section.accessibilityIdentifier)
        .accessibilityValue(selection == section ? "Selected" : "")
    }
}
