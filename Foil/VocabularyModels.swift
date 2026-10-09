import Foundation

struct VocabularyCorrection: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var writtenAs: String
    var correctVersion: String
    var note: String?
    var sourceRecordID: UUID?
    var sourceAppName: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        writtenAs: String,
        correctVersion: String,
        note: String? = nil,
        sourceRecordID: UUID? = nil,
        sourceAppName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.writtenAs = writtenAs
        self.correctVersion = correctVersion
        self.note = note
        self.sourceRecordID = sourceRecordID
        self.sourceAppName = sourceAppName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct VocabularyTerm: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    /// nil is global. A missing or disabled group never widens a term to global.
    var scopeID: String?
    var term: String
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        term: String,
        note: String? = nil,
        scopeID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.scopeID = scopeID
        self.term = term
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Shared identity and resolution for UI, storage, and agent Vocabulary operations.
enum PreferredTermPolicy {
    static let maximumPhraseScalars = 256

    static func normalized(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    static func identity(_ term: String) -> String {
        normalized(term).folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func validPhrase(_ term: String) -> Bool {
        !normalized(term).isEmpty && term.unicodeScalars.count <= maximumPhraseScalars &&
            !term.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    /// Existing releases allowed longer/control-containing global terms. Loading must preserve them.
    static func isValidStored(_ terms: [VocabularyTerm]) -> Bool {
        var ids = Set<UUID>()
        var identities = Set<TermIdentity>()
        return terms.allSatisfy { term in
            ids.insert(term.id).inserted && !normalized(term.term).isEmpty &&
                term.createdAt <= term.updatedAt &&
                (term.scopeID.map { validPhrase($0) && $0 != "global" && $0 == normalized($0) } ?? true) &&
                identities.insert(TermIdentity(scopeID: term.scopeID, text: identity(term.term))).inserted
        }
    }

    static func isValid(_ terms: [VocabularyTerm]) -> Bool {
        isValidStored(terms) && terms.allSatisfy { validPhrase($0.term) }
    }

    static func validChanges(_ terms: [VocabularyTerm], from existing: [VocabularyTerm]) -> Bool {
        guard isValidStored(terms) else { return false }
        return terms.allSatisfy { term in
            validPhrase(term.term) || existing.contains {
                $0.id == term.id && $0.scopeID == term.scopeID && $0.term.utf8.elementsEqual(term.term.utf8)
            }
        }
    }

    /// The caller supplies an enabled, explicitly resolved group, or nil for global only.
    static func effective(_ terms: [VocabularyTerm], groupID: String?) -> [String] {
        var result: [String] = []
        var indices: [String: Int] = [:]
        for term in terms where term.scopeID == nil {
            let key = identity(term.term)
            if indices[key] == nil { indices[key] = result.count; result.append(term.term) }
        }
        if let groupID {
            for term in terms where term.scopeID == groupID {
                let key = identity(term.term)
                if let index = indices[key] { result[index] = term.term }
                else { indices[key] = result.count; result.append(term.term) }
            }
        }
        return result
    }

    private struct TermIdentity: Hashable {
        let scopeID: String?
        let text: String
    }
}
