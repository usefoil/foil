import Foundation

struct VocabularyCorrection: Codable, Identifiable, Equatable {
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

struct VocabularyTerm: Codable, Identifiable, Equatable {
    var id: UUID
    var term: String
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        term: String,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.term = term
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
