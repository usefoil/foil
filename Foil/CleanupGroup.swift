import Foundation

extension TranscriptCleanupProviderID: Codable {}

struct CleanupAppContext: Equatable {
    var displayName: String?
    var bundleIdentifier: String?
    var appPath: String?

    init(displayName: String? = nil, bundleIdentifier: String? = nil, appPath: String? = nil) {
        self.displayName = Self.normalized(displayName)
        self.bundleIdentifier = Self.normalized(bundleIdentifier)
        self.appPath = Self.normalized(appPath)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct CleanupAppMatcher: Codable, Equatable, Identifiable {
    var id: UUID
    var displayName: String
    var bundleIdentifier: String?
    var appPath: String?

    init(
        id: UUID = UUID(),
        displayName: String,
        bundleIdentifier: String? = nil,
        appPath: String? = nil
    ) {
        self.id = id
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleIdentifier = Self.normalizedOptional(bundleIdentifier)
        self.appPath = Self.normalizedOptional(appPath)
    }

    var membershipKey: String? {
        if let bundleIdentifier {
            return "bundle:\(bundleIdentifier.lowercased())"
        }
        if let appPath {
            return "path:\(appPath.lowercased())"
        }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : "name:\(trimmedName.lowercased())"
    }

    func matches(_ context: CleanupAppContext) -> Bool {
        if let bundleIdentifier, let contextBundleIdentifier = context.bundleIdentifier {
            return bundleIdentifier.caseInsensitiveCompare(contextBundleIdentifier) == .orderedSame
        }
        if let appPath, let contextAppPath = context.appPath {
            return appPath.caseInsensitiveCompare(contextAppPath) == .orderedSame
        }
        guard let contextDisplayName = context.displayName else { return false }
        return displayName.caseInsensitiveCompare(contextDisplayName) == .orderedSame
    }

    func normalized() -> CleanupAppMatcher? {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBundleIdentifier = Self.normalizedOptional(bundleIdentifier)
        let normalizedAppPath = Self.normalizedOptional(appPath)
        guard !normalizedName.isEmpty || normalizedBundleIdentifier != nil || normalizedAppPath != nil else {
            return nil
        }
        return CleanupAppMatcher(
            id: id,
            displayName: normalizedName.isEmpty ? normalizedBundleIdentifier ?? normalizedAppPath ?? "Unknown app" : normalizedName,
            bundleIdentifier: normalizedBundleIdentifier,
            appPath: normalizedAppPath
        )
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum RunningAppCandidatePolicy {
    private static let foilBundleIdentifiers: Set<String> = [
        AppBrand.productionBundleIdentifier.lowercased(),
        AppBrand.developmentBundleIdentifier.lowercased(),
        "com.neonwatty.FoilE2E".lowercased()
    ]

    private static let nonTextBundleIdentifiers: Set<String> = [
        "com.apple.ActivityMonitor".lowercased(),
        "com.apple.AppStore".lowercased(),
        "com.apple.Console".lowercased(),
        "com.apple.DiskUtility".lowercased(),
        "com.apple.Preview".lowercased(),
        "com.apple.finder".lowercased(),
        "com.apple.Photos".lowercased(),
        "com.apple.systempreferences".lowercased()
    ]

    private static let nonTextDisplayNames: Set<String> = [
        "activity monitor",
        "app store",
        "console",
        "disk utility",
        "finder",
        "foil",
        "foil dev",
        "photos",
        "preview",
        "system preferences",
        "system settings"
    ]

    static func allows(
        displayName: String,
        bundleIdentifier: String?,
        appPath: String?,
        currentBundleIdentifier: String = AppBrand.bundleIdentifier
    ) -> Bool {
        let normalizedBundleIdentifier = bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedCurrentBundleIdentifier = currentBundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let normalizedBundleIdentifier,
           normalizedBundleIdentifier == normalizedCurrentBundleIdentifier
                || foilBundleIdentifiers.contains(normalizedBundleIdentifier)
                || nonTextBundleIdentifiers.contains(normalizedBundleIdentifier) {
            return false
        }

        let normalizedDisplayName = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if nonTextDisplayNames.contains(normalizedDisplayName) {
            return false
        }

        let appFileName = appPath
            .map { URL(fileURLWithPath: $0).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if appFileName == "foil.app" || appFileName == "foil dev.app" {
            return false
        }

        return true
    }

    static func allows(_ matcher: CleanupAppMatcher, currentBundleIdentifier: String = AppBrand.bundleIdentifier) -> Bool {
        allows(
            displayName: matcher.displayName,
            bundleIdentifier: matcher.bundleIdentifier,
            appPath: matcher.appPath,
            currentBundleIdentifier: currentBundleIdentifier
        )
    }
}

struct CleanupGroup: Codable, Equatable, Identifiable {
    static let defaultGroupID = "default-unassigned-apps"
    static let defaultGroupName = "Default for unassigned apps"

    var id: String
    var name: String
    var sortOrder: Int
    var isEnabled: Bool
    var appMatchers: [CleanupAppMatcher]
    var processingMode: TranscriptProcessingMode
    var cleanupProviderID: TranscriptCleanupProviderID
    var cleanupModel: String
    var customCleanupBaseURL: String?
    var customPrompt: String?
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        sortOrder: Int = 0,
        isEnabled: Bool = true,
        appMatchers: [CleanupAppMatcher] = [],
        processingMode: TranscriptProcessingMode = .raw,
        cleanupProviderID: TranscriptCleanupProviderID = .groq,
        cleanupModel: String = "llama-3.1-8b-instant",
        customCleanupBaseURL: String? = nil,
        customPrompt: String? = nil,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.isEnabled = isEnabled
        self.appMatchers = appMatchers
        self.processingMode = processingMode.normalizedActiveMode
        self.cleanupProviderID = cleanupProviderID
        self.cleanupModel = cleanupModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.customCleanupBaseURL = Self.normalizedOptional(customCleanupBaseURL)
        self.customPrompt = Self.normalizedOptional(customPrompt)
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func defaultGroup(
        processingMode: TranscriptProcessingMode = .raw,
        cleanupProviderID: TranscriptCleanupProviderID = .groq,
        cleanupModel: String = "llama-3.1-8b-instant",
        customCleanupBaseURL: String? = nil,
        customPrompt: String? = nil,
        now: Date = Date()
    ) -> CleanupGroup {
        CleanupGroup(
            id: defaultGroupID,
            name: defaultGroupName,
            sortOrder: 0,
            isEnabled: true,
            processingMode: processingMode,
            cleanupProviderID: cleanupProviderID,
            cleanupModel: cleanupModel,
            customCleanupBaseURL: customCleanupBaseURL,
            customPrompt: customPrompt,
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
    }

    var normalizedCustomPrompt: String? {
        Self.normalizedOptional(customPrompt)
    }

    var normalizedCustomCleanupBaseURL: String? {
        Self.normalizedOptional(customCleanupBaseURL)
    }

    func normalized(isDefault defaultMarker: Bool? = nil, sortOrder normalizedSortOrder: Int? = nil) -> CleanupGroup {
        var normalized = self
        normalized.id = (defaultMarker ?? isDefault) ? Self.defaultGroupID : id.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.id.isEmpty {
            normalized.id = UUID().uuidString
        }
        normalized.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.name.isEmpty {
            normalized.name = (defaultMarker ?? isDefault) ? Self.defaultGroupName : "Cleanup Group"
        }
        normalized.sortOrder = normalizedSortOrder ?? sortOrder
        normalized.isDefault = defaultMarker ?? isDefault
        if normalized.isDefault {
            normalized.id = Self.defaultGroupID
            normalized.name = Self.defaultGroupName
            normalized.isEnabled = true
            normalized.sortOrder = 0
        }
        normalized.processingMode = processingMode.normalizedActiveMode
        normalized.cleanupModel = cleanupModel.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.customCleanupBaseURL = Self.normalizedOptional(customCleanupBaseURL)
        normalized.customPrompt = Self.normalizedOptional(customPrompt)
        normalized.appMatchers = appMatchers.compactMap { $0.normalized() }
        return normalized
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct CleanupGroupResolution: Equatable {
    let group: CleanupGroup
    let provider: TranscriptCleanupProvider
    let customPrompt: String?

    var processingMode: TranscriptProcessingMode {
        group.processingMode
    }
}

enum CleanupGroupResolver {
    static func normalizedGroups(_ groups: [CleanupGroup], now: Date = Date()) -> [CleanupGroup] {
        var sourceGroups = groups
        if !sourceGroups.contains(where: { $0.isDefault || $0.id == CleanupGroup.defaultGroupID }) {
            sourceGroups.insert(CleanupGroup.defaultGroup(now: now), at: 0)
        }

        let firstDefaultIndex = sourceGroups.firstIndex { $0.isDefault || $0.id == CleanupGroup.defaultGroupID }
        var normalizedGroups: [CleanupGroup] = []
        var claimedMatcherKeys: [String: Int] = [:]

        for index in sourceGroups.indices {
            let isDefault = index == firstDefaultIndex
            var group = sourceGroups[index].normalized(
                isDefault: isDefault,
                sortOrder: isDefault ? 0 : max(1, sourceGroups[index].sortOrder)
            )
            group.appMatchers = group.appMatchers.filter { matcher in
                guard let key = matcher.membershipKey else { return false }
                if let previousGroupIndex = claimedMatcherKeys[key],
                   previousGroupIndex < normalizedGroups.count {
                    normalizedGroups[previousGroupIndex].appMatchers.removeAll { $0.membershipKey == key }
                }
                claimedMatcherKeys[key] = normalizedGroups.count
                return true
            }
            normalizedGroups.append(group)
        }

        return normalizedGroups.sorted {
            if $0.isDefault != $1.isDefault {
                return $0.isDefault
            }
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func resolve(
        appContext: CleanupAppContext?,
        groups: [CleanupGroup],
        providerFactory: (CleanupGroup) -> TranscriptCleanupProvider
    ) -> CleanupGroupResolution {
        let normalizedGroups = normalizedGroups(groups)
        let defaultGroup = normalizedGroups.first(where: \.isDefault)
            ?? CleanupGroup.defaultGroup()
        let matchedGroup: CleanupGroup?
        if let appContext {
            matchedGroup = normalizedGroups.first { group in
                !group.isDefault && group.isEnabled && group.appMatchers.contains { $0.matches(appContext) }
            }
        } else {
            matchedGroup = nil
        }
        let resolvedGroup = matchedGroup ?? defaultGroup
        let provider = resolvedGroup.processingMode == .raw ? .none : providerFactory(resolvedGroup)
        return CleanupGroupResolution(
            group: resolvedGroup,
            provider: provider,
            customPrompt: resolvedGroup.normalizedCustomPrompt
        )
    }
}
