import Foundation

struct LocalCorrectionRule: Codable, Equatable, Sendable {
    let id: String
    let source: String
    let replacement: String
    let group: String?
    let enabled: Bool
    let caseSensitive: Bool

    enum CodingKeys: String, CodingKey {
        case id, source, replacement, group, enabled
        case caseSensitive = "case_sensitive"
    }
}

enum LocalCorrectionFallbackReason: String, Equatable, Sendable {
    case processingDisabled
    case inputTooLarge
}

struct LocalCorrectionResult: Equatable, Sendable {
    let text: String
    let replacementCount: Int
    let fallbackReason: LocalCorrectionFallbackReason?
}

enum LocalCorrectionValidationError: Error, Equatable, CustomStringConvertible {
    case duplicateRuleID(String)
    case ambiguousAlias(String, String)
    case emptyRuleID
    case emptySource(String)
    case emptyReplacement(String)
    case phraseTooLong(String)
    case tooManyEnabledRules(Int)

    var description: String {
        switch self {
        case .duplicateRuleID(let id):
            "Duplicate local correction rule ID: \(id)"
        case .ambiguousAlias(let first, let second):
            "Ambiguous local correction aliases: \(first), \(second)"
        case .emptyRuleID:
            "A local correction rule ID cannot be empty"
        case .emptySource(let id):
            "Local correction rule \(id) has an empty source"
        case .emptyReplacement(let id):
            "Local correction rule \(id) has an empty replacement"
        case .phraseTooLong(let id):
            "Local correction rule \(id) exceeds 256 Unicode scalars"
        case .tooManyEnabledRules(let count):
            "Local corrections support at most 1,000 enabled rules (received \(count))"
        }
    }
}

struct CompiledLocalCorrections: Sendable {
    fileprivate struct Rule: Sendable {
        let id: String
        let replacement: String
        let replacementUTF8: [UInt8]
        let group: String?
        let scalarCount: Int
    }

    fileprivate struct TrieNode: Sendable {
        var children: [UInt32: Int] = [:]
        var terminalRuleIndexes: [Int] = []
    }

    fileprivate let rules: [Rule]
    fileprivate let sensitiveTrie: [TrieNode]
    fileprivate let insensitiveTrie: [TrieNode]
}

struct LocalCorrectionExecutionSnapshot: Sendable {
    let revision: Int
    let enabled: Bool
    let compiled: CompiledLocalCorrections
}

enum LocalCorrectionEngine {
    static let maximumInputBytes = 65_536
    static let maximumEnabledRules = 1_000
    static let maximumPhraseScalars = 256

    static func compile(_ rules: [LocalCorrectionRule]) throws -> CompiledLocalCorrections {
        try validate(rules)

        var compiledRules: [CompiledLocalCorrections.Rule] = []
        var sensitiveTrie = [CompiledLocalCorrections.TrieNode()]
        var insensitiveTrie = [CompiledLocalCorrections.TrieNode()]

        for rule in rules where rule.enabled {
            let scalars = normalizedScalars(rule.source)
            let compiledIndex = compiledRules.count
            compiledRules.append(
                .init(
                    id: rule.id,
                    replacement: rule.replacement,
                    replacementUTF8: Array(rule.replacement.utf8),
                    group: rule.group,
                    scalarCount: scalars.count
                )
            )
            if rule.caseSensitive {
                insert(scalars, ruleIndex: compiledIndex, into: &sensitiveTrie)
            } else {
                insert(scalars.map(asciiFold), ruleIndex: compiledIndex, into: &insensitiveTrie)
            }
        }

        return CompiledLocalCorrections(
            rules: compiledRules,
            sensitiveTrie: sensitiveTrie,
            insensitiveTrie: insensitiveTrie
        )
    }

    static func correct(
        _ input: String,
        activeGroup: String?,
        enabled: Bool,
        compiled: CompiledLocalCorrections
    ) -> LocalCorrectionResult {
        guard enabled else {
            return LocalCorrectionResult(text: input, replacementCount: 0, fallbackReason: .processingDisabled)
        }
        guard !input.isEmpty,
              compiled.rules.contains(where: { $0.group == nil || $0.group == activeGroup }) else {
            return LocalCorrectionResult(text: input, replacementCount: 0, fallbackReason: nil)
        }
        guard input.utf8.count <= maximumInputBytes else {
            return LocalCorrectionResult(text: input, replacementCount: 0, fallbackReason: .inputTooLarge)
        }

        let inputUTF8 = input.utf8
        if inputUTF8.allSatisfy({ $0 < 128 }) {
            let bytes = Array(inputUTF8)
            if !containsProtectedSyntaxASCII(bytes) {
                return correctUnprotectedASCII(
                    bytes,
                    original: input,
                    activeGroup: activeGroup,
                    compiled: compiled
                )
            }
        }

        let normalized = NormalizedInput(input)
        let protectedRanges = protectedRanges(in: input)
        var scalarPosition = 0
        var copyStart = input.startIndex
        var output = ""
        var replacementCount = 0

        while scalarPosition < normalized.scalars.count {
            guard normalized.isCharacterStart(at: scalarPosition) else {
                scalarPosition += 1
                continue
            }

            let match = bestMatch(
                at: scalarPosition,
                normalized: normalized,
                activeGroup: activeGroup,
                compiled: compiled,
                protectedRanges: protectedRanges
            )
            if let match {
                let originalStart = normalized.originalStarts[scalarPosition]
                let originalEnd = normalized.originalEnds[match.endScalarPosition - 1]
                output.append(contentsOf: input[copyStart..<originalStart])
                output.append(match.rule.replacement)
                copyStart = originalEnd
                scalarPosition = match.endScalarPosition
                replacementCount += 1
            } else {
                scalarPosition = nextCandidatePosition(
                    afterFailedMatchAt: scalarPosition,
                    normalized: normalized
                )
            }
        }

        guard replacementCount > 0 else {
            return LocalCorrectionResult(text: input, replacementCount: 0, fallbackReason: nil)
        }
        output.append(contentsOf: input[copyStart..<input.endIndex])
        return LocalCorrectionResult(text: output, replacementCount: replacementCount, fallbackReason: nil)
    }

    private struct Match {
        let rule: CompiledLocalCorrections.Rule
        let endScalarPosition: Int
    }

    private struct ASCIIMatch {
        let ruleIndex: Int
        let endBytePosition: Int
    }

    private static func correctUnprotectedASCII(
        _ input: [UInt8],
        original: String,
        activeGroup: String?,
        compiled: CompiledLocalCorrections
    ) -> LocalCorrectionResult {
        var position = 0
        var copyStart = 0
        var replacements: [(start: Int, match: ASCIIMatch)] = []

        while position < input.count {
            if !isASCIICharacterStart(input, at: position) {
                position += 1
                continue
            }
            if position > 0, isBoundaryBlockingASCII(input[position - 1]) {
                position += 1
                continue
            }

            if let match = bestASCIIMatch(
                at: position,
                input: input,
                activeGroup: activeGroup,
                compiled: compiled
            ) {
                replacements.append((position, match))
                position = match.endBytePosition
            } else if isBoundaryBlockingASCII(input[position]) {
                repeat {
                    position += 1
                } while position < input.count && isBoundaryBlockingASCII(input[position])
            } else {
                position += 1
            }
        }

        guard !replacements.isEmpty else {
            return LocalCorrectionResult(text: original, replacementCount: 0, fallbackReason: nil)
        }

        var output: [UInt8] = []
        output.reserveCapacity(input.count)
        for replacement in replacements {
            output.append(contentsOf: input[copyStart..<replacement.start])
            output.append(contentsOf: compiled.rules[replacement.match.ruleIndex].replacementUTF8)
            copyStart = replacement.match.endBytePosition
        }
        output.append(contentsOf: input[copyStart..<input.count])
        return LocalCorrectionResult(
            text: String(decoding: output, as: UTF8.self),
            replacementCount: replacements.count,
            fallbackReason: nil
        )
    }

    private static func bestASCIIMatch(
        at start: Int,
        input: [UInt8],
        activeGroup: String?,
        compiled: CompiledLocalCorrections
    ) -> ASCIIMatch? {
        var best: ASCIIMatch?
        if compiled.sensitiveTrie.count > 1 {
            scanASCIITrie(
                compiled.sensitiveTrie,
                folded: false,
                start: start,
                input: input,
                activeGroup: activeGroup,
                compiled: compiled,
                best: &best
            )
        }
        if compiled.insensitiveTrie.count > 1 {
            scanASCIITrie(
                compiled.insensitiveTrie,
                folded: true,
                start: start,
                input: input,
                activeGroup: activeGroup,
                compiled: compiled,
                best: &best
            )
        }
        return best
    }

    private static func scanASCIITrie(
        _ trie: [CompiledLocalCorrections.TrieNode],
        folded: Bool,
        start: Int,
        input: [UInt8],
        activeGroup: String?,
        compiled: CompiledLocalCorrections,
        best: inout ASCIIMatch?
    ) {
        var nodeIndex = 0
        var position = start
        while position < input.count {
            let byte = folded ? asciiFold(input[position]) : input[position]
            guard let nextNode = trie[nodeIndex].children[UInt32(byte)] else { return }
            nodeIndex = nextNode
            position += 1

            guard !trie[nodeIndex].terminalRuleIndexes.isEmpty,
                  isASCIICharacterEnd(input, at: position),
                  position == input.count || !isBoundaryBlockingASCII(input[position]) else {
                continue
            }
            for ruleIndex in trie[nodeIndex].terminalRuleIndexes {
                let rule = compiled.rules[ruleIndex]
                guard rule.group == nil || rule.group == activeGroup else { continue }
                let candidate = ASCIIMatch(ruleIndex: ruleIndex, endBytePosition: position)
                if isPreferredASCII(candidate, over: best, rules: compiled.rules) {
                    best = candidate
                }
            }
        }
    }

    private static func isPreferredASCII(
        _ candidate: ASCIIMatch,
        over current: ASCIIMatch?,
        rules: [CompiledLocalCorrections.Rule]
    ) -> Bool {
        guard let current else { return true }
        let candidateRule = rules[candidate.ruleIndex]
        let currentRule = rules[current.ruleIndex]
        let candidateScoped = candidateRule.group == nil ? 0 : 1
        let currentScoped = currentRule.group == nil ? 0 : 1
        if candidateScoped != currentScoped { return candidateScoped > currentScoped }
        if candidateRule.scalarCount != currentRule.scalarCount {
            return candidateRule.scalarCount > currentRule.scalarCount
        }
        return candidateRule.id < currentRule.id
    }

    private static func containsProtectedSyntaxASCII(_ input: [UInt8]) -> Bool {
        var index = 0
        while index < input.count {
            let byte = input[index]
            if byte == 96 || byte == 126 { return true }
            let folded = asciiFold(byte)
            if folded == 104,
               matchesASCIIPrefix([104, 116, 116, 112, 58, 47, 47], in: input, at: index) ||
                matchesASCIIPrefix([104, 116, 116, 112, 115, 58, 47, 47], in: input, at: index) {
                return true
            }
            if folded == 119,
               matchesASCIIPrefix([119, 119, 119, 46], in: input, at: index) {
                return true
            }
            index += 1
        }
        return false
    }

    private static func matchesASCIIPrefix(_ prefix: [UInt8], in input: [UInt8], at start: Int) -> Bool {
        guard start + prefix.count <= input.count else { return false }
        for offset in prefix.indices where asciiFold(input[start + offset]) != prefix[offset] {
            return false
        }
        return true
    }

    private static func asciiFold(_ byte: UInt8) -> UInt8 {
        byte >= 65 && byte <= 90 ? byte + 32 : byte
    }

    private static func isBoundaryBlockingASCII(_ byte: UInt8) -> Bool {
        byte == 95 ||
            (byte >= 48 && byte <= 57) ||
            (byte >= 65 && byte <= 90) ||
            (byte >= 97 && byte <= 122)
    }

    private static func isASCIICharacterStart(_ input: [UInt8], at position: Int) -> Bool {
        position == 0 || input[position] != 10 || input[position - 1] != 13
    }

    private static func isASCIICharacterEnd(_ input: [UInt8], at position: Int) -> Bool {
        position == input.count || input[position - 1] != 13 || input[position] != 10
    }

    private struct NormalizedInput {
        let scalars: [UInt32]
        let originalStarts: [String.Index]
        let originalEnds: [String.Index]
        let isASCII: Bool

        init(_ input: String) {
            let utf8 = input.utf8
            if utf8.allSatisfy({ $0 < 128 }) {
                var scalars: [UInt32] = []
                var starts: [String.Index] = []
                var ends: [String.Index] = []
                scalars.reserveCapacity(utf8.count)
                starts.reserveCapacity(utf8.count)
                ends.reserveCapacity(utf8.count)
                var index = utf8.startIndex
                while index < utf8.endIndex {
                    let next = utf8.index(after: index)
                    scalars.append(UInt32(utf8[index]))
                    starts.append(index)
                    ends.append(next)
                    index = next
                }
                self.scalars = scalars
                originalStarts = starts
                originalEnds = ends
                isASCII = true
                return
            }

            var scalars: [UInt32] = []
            var starts: [String.Index] = []
            var ends: [String.Index] = []
            var index = input.startIndex
            while index < input.endIndex {
                let next = input.index(after: index)
                let character = String(input[index..<next])
                let characterScalars = character.unicodeScalars.allSatisfy { $0.value < 128 }
                    ? character.unicodeScalars.map(\.value)
                    : character.precomposedStringWithCanonicalMapping.unicodeScalars.map(\.value)
                for scalar in characterScalars {
                    scalars.append(scalar)
                    starts.append(index)
                    ends.append(next)
                }
                index = next
            }
            self.scalars = scalars
            originalStarts = starts
            originalEnds = ends
            isASCII = false
        }

        func isCharacterStart(at position: Int) -> Bool {
            isASCII || position == 0 || originalStarts[position] != originalStarts[position - 1]
        }

        func isCharacterEnd(at position: Int) -> Bool {
            isASCII || position == scalars.count || originalStarts[position] != originalStarts[position - 1]
        }
    }

    private static func nextCandidatePosition(
        afterFailedMatchAt start: Int,
        normalized: NormalizedInput
    ) -> Int {
        var position = start
        let characterStart = normalized.originalStarts[position]
        repeat {
            position += 1
        } while position < normalized.scalars.count &&
            normalized.originalStarts[position] == characterStart

        guard isBoundaryBlocking(normalized.scalars[start]) else { return position }
        while position < normalized.scalars.count,
              isBoundaryBlocking(normalized.scalars[position]) {
            let nextCharacterStart = normalized.originalStarts[position]
            repeat {
                position += 1
            } while position < normalized.scalars.count &&
                normalized.originalStarts[position] == nextCharacterStart
        }
        return position
    }

    private static func bestMatch(
        at start: Int,
        normalized: NormalizedInput,
        activeGroup: String?,
        compiled: CompiledLocalCorrections,
        protectedRanges: [Range<String.Index>]
    ) -> Match? {
        guard !isBoundaryBlocking(normalized.scalars[safe: start - 1]) else { return nil }

        var best: Match?
        if compiled.sensitiveTrie.count > 1 {
            scanTrie(
                compiled.sensitiveTrie,
                folded: false,
                start: start,
                normalized: normalized,
                activeGroup: activeGroup,
                compiled: compiled,
                protectedRanges: protectedRanges,
                best: &best
            )
        }
        if compiled.insensitiveTrie.count > 1 {
            scanTrie(
                compiled.insensitiveTrie,
                folded: true,
                start: start,
                normalized: normalized,
                activeGroup: activeGroup,
                compiled: compiled,
                protectedRanges: protectedRanges,
                best: &best
            )
        }
        return best
    }

    private static func scanTrie(
        _ trie: [CompiledLocalCorrections.TrieNode],
        folded: Bool,
        start: Int,
        normalized: NormalizedInput,
        activeGroup: String?,
        compiled: CompiledLocalCorrections,
        protectedRanges: [Range<String.Index>],
        best: inout Match?
    ) {
        var nodeIndex = 0
        var position = start
        while position < normalized.scalars.count {
            let scalar = folded ? asciiFold(normalized.scalars[position]) : normalized.scalars[position]
            guard let nextNode = trie[nodeIndex].children[scalar] else { return }
            nodeIndex = nextNode
            position += 1

            guard !trie[nodeIndex].terminalRuleIndexes.isEmpty,
                  normalized.isCharacterEnd(at: position),
                  !isBoundaryBlocking(normalized.scalars[safe: position]) else {
                continue
            }

            if !protectedRanges.isEmpty {
                let originalRange = normalized.originalStarts[start]..<normalized.originalEnds[position - 1]
                guard !protectedRanges.contains(where: { rangesOverlap(originalRange, $0) }) else { continue }
            }

            for ruleIndex in trie[nodeIndex].terminalRuleIndexes {
                let rule = compiled.rules[ruleIndex]
                guard rule.group == nil || rule.group == activeGroup else { continue }
                let candidate = Match(rule: rule, endScalarPosition: position)
                if isPreferred(candidate, over: best) {
                    best = candidate
                }
            }
        }
    }

    private static func isPreferred(_ candidate: Match, over current: Match?) -> Bool {
        guard let current else { return true }
        let candidateScoped = candidate.rule.group == nil ? 0 : 1
        let currentScoped = current.rule.group == nil ? 0 : 1
        if candidateScoped != currentScoped { return candidateScoped > currentScoped }
        if candidate.rule.scalarCount != current.rule.scalarCount {
            return candidate.rule.scalarCount > current.rule.scalarCount
        }
        return candidate.rule.id < current.rule.id
    }

    private static func validate(_ rules: [LocalCorrectionRule]) throws {
        let enabledCount = rules.lazy.filter(\.enabled).count
        guard enabledCount <= maximumEnabledRules else {
            throw LocalCorrectionValidationError.tooManyEnabledRules(enabledCount)
        }

        var ids = Set<String>()
        var prior: [(rule: LocalCorrectionRule, normalized: [UInt32], folded: [UInt32])] = []
        for rule in rules {
            guard !rule.id.isEmpty else { throw LocalCorrectionValidationError.emptyRuleID }
            guard ids.insert(rule.id).inserted else {
                throw LocalCorrectionValidationError.duplicateRuleID(rule.id)
            }
            guard !rule.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LocalCorrectionValidationError.emptySource(rule.id)
            }
            guard !rule.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LocalCorrectionValidationError.emptyReplacement(rule.id)
            }
            guard rule.source.unicodeScalars.count <= maximumPhraseScalars,
                  rule.replacement.unicodeScalars.count <= maximumPhraseScalars else {
                throw LocalCorrectionValidationError.phraseTooLong(rule.id)
            }
            let normalized = normalizedScalars(rule.source)
            let folded = normalized.map(asciiFold)
            for previous in prior where previous.rule.group == rule.group {
                let overlaps = previous.rule.caseSensitive && rule.caseSensitive
                    ? previous.normalized == normalized
                    : previous.folded == folded
                if overlaps {
                    throw LocalCorrectionValidationError.ambiguousAlias(previous.rule.id, rule.id)
                }
            }
            prior.append((rule, normalized, folded))
        }
    }

    private static func insert(
        _ scalars: [UInt32],
        ruleIndex: Int,
        into trie: inout [CompiledLocalCorrections.TrieNode]
    ) {
        var nodeIndex = 0
        for scalar in scalars {
            if let child = trie[nodeIndex].children[scalar] {
                nodeIndex = child
            } else {
                let child = trie.count
                trie.append(.init())
                trie[nodeIndex].children[scalar] = child
                nodeIndex = child
            }
        }
        trie[nodeIndex].terminalRuleIndexes.append(ruleIndex)
    }

    private static func normalizedScalars(_ value: String) -> [UInt32] {
        value.flatMap { character -> [UInt32] in
            let text = String(character)
            if text.unicodeScalars.allSatisfy({ $0.value < 128 }) {
                return text.unicodeScalars.map(\.value)
            }
            return text.precomposedStringWithCanonicalMapping.unicodeScalars.map(\.value)
        }
    }

    private static func asciiFold(_ scalar: UInt32) -> UInt32 {
        scalar >= 65 && scalar <= 90 ? scalar + 32 : scalar
    }

    private static func isBoundaryBlocking(_ value: UInt32?) -> Bool {
        guard let value else { return false }
        if value < 128 {
            return value == 95 ||
                (value >= 48 && value <= 57) ||
                (value >= 65 && value <= 90) ||
                (value >= 97 && value <= 122)
        }
        guard let scalar = Unicode.Scalar(value) else { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber,
             .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return false
        }
    }

    private static func rangesOverlap(_ first: Range<String.Index>, _ second: Range<String.Index>) -> Bool {
        first.lowerBound < second.upperBound && second.lowerBound < first.upperBound
    }

    private struct Line {
        let start: String.Index
        let contentEnd: String.Index
        let totalEnd: String.Index
    }

    private static func protectedRanges(in input: String) -> [Range<String.Index>] {
        let hasCodeDelimiter = input.contains("`") || input.contains("~")
        let hasURLPrefix = input.range(of: "http://", options: .caseInsensitive) != nil ||
            input.range(of: "https://", options: .caseInsensitive) != nil ||
            input.range(of: "www.", options: .caseInsensitive) != nil
        guard hasCodeDelimiter || hasURLPrefix else { return [] }

        let lines = hasCodeDelimiter ? lineRanges(in: input) : []
        let fenceRanges = hasCodeDelimiter ? fencedRanges(in: input, lines: lines) : []
        var ranges = fenceRanges
        if hasCodeDelimiter {
            ranges.append(contentsOf: inlineCodeRanges(in: input, lines: lines, fenceRanges: fenceRanges))
        }
        if hasURLPrefix {
            ranges.append(contentsOf: urlRanges(in: input))
        }
        return ranges
    }

    private static func lineRanges(in input: String) -> [Line] {
        guard !input.isEmpty else { return [] }
        var lines: [Line] = []
        var start = input.startIndex
        var index = start
        while index < input.endIndex {
            if input[index] == "\n" || input[index] == "\r\n" {
                let totalEnd = input.index(after: index)
                lines.append(Line(start: start, contentEnd: index, totalEnd: totalEnd))
                start = totalEnd
            }
            index = input.index(after: index)
        }
        if start < input.endIndex {
            lines.append(Line(start: start, contentEnd: input.endIndex, totalEnd: input.endIndex))
        }
        return lines
    }

    private static func fencedRanges(in input: String, lines: [Line]) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var open: (start: String.Index, marker: Character, length: Int)?

        for line in lines {
            if let active = open {
                if isFenceClose(line, in: input, marker: active.marker, minimumLength: active.length) {
                    ranges.append(active.start..<line.totalEnd)
                    open = nil
                }
            } else if let opening = fenceOpening(line, in: input) {
                open = (line.start, opening.marker, opening.length)
            }
        }
        if let open {
            ranges.append(open.start..<input.endIndex)
        }
        return ranges
    }

    private static func fenceOpening(_ line: Line, in input: String) -> (marker: Character, length: Int)? {
        var index = line.start
        var leadingSpaces = 0
        while index < line.contentEnd, input[index] == " ", leadingSpaces < 3 {
            leadingSpaces += 1
            index = input.index(after: index)
        }
        guard index < line.contentEnd, input[index] == "`" || input[index] == "~" else { return nil }
        let marker = input[index]
        let length = runLength(of: marker, from: index, until: line.contentEnd, in: input)
        return length >= 3 ? (marker, length) : nil
    }

    private static func isFenceClose(
        _ line: Line,
        in input: String,
        marker: Character,
        minimumLength: Int
    ) -> Bool {
        var index = line.start
        var leadingSpaces = 0
        while index < line.contentEnd, input[index] == " ", leadingSpaces < 3 {
            leadingSpaces += 1
            index = input.index(after: index)
        }
        guard index < line.contentEnd, input[index] == marker else { return false }
        let length = runLength(of: marker, from: index, until: line.contentEnd, in: input)
        guard length >= minimumLength else { return false }
        var remainder = index
        for _ in 0..<length { remainder = input.index(after: remainder) }
        return input[remainder..<line.contentEnd].allSatisfy(\.isWhitespace)
    }

    private static func inlineCodeRanges(
        in input: String,
        lines: [Line],
        fenceRanges: [Range<String.Index>]
    ) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        for line in lines {
            let lineRange = line.start..<line.totalEnd
            guard !fenceRanges.contains(where: { rangesOverlap(lineRange, $0) }) else { continue }
            var index = line.start
            while index < line.contentEnd {
                guard input[index] == "`" else {
                    index = input.index(after: index)
                    continue
                }
                let openingLength = runLength(of: "`", from: index, until: line.contentEnd, in: input)
                let openingStart = index
                for _ in 0..<openingLength { index = input.index(after: index) }
                var search = index
                var closingEnd: String.Index?
                while search < line.contentEnd {
                    guard input[search] == "`" else {
                        search = input.index(after: search)
                        continue
                    }
                    let closingLength = runLength(of: "`", from: search, until: line.contentEnd, in: input)
                    var runEnd = search
                    for _ in 0..<closingLength { runEnd = input.index(after: runEnd) }
                    if closingLength == openingLength {
                        closingEnd = runEnd
                        break
                    }
                    search = runEnd
                }
                let end = closingEnd ?? line.contentEnd
                ranges.append(openingStart..<end)
                index = end
            }
        }
        return ranges
    }

    private static func urlRanges(in input: String) -> [Range<String.Index>] {
        let prefixes = ["https://", "http://", "www."]
        var ranges: [Range<String.Index>] = []
        var index = input.startIndex
        while index < input.endIndex {
            let hasTokenBoundary: Bool
            if index == input.startIndex {
                hasTokenBoundary = true
            } else {
                let previous = input.index(before: index)
                hasTokenBoundary = !isBoundaryBlocking(String(input[previous]).unicodeScalars.last?.value)
            }
            if hasTokenBoundary,
               let prefix = prefixes.first(where: { hasASCIIPrefix($0, in: input, at: index) }) {
                var end = index
                for _ in prefix { end = input.index(after: end) }
                while end < input.endIndex {
                    let character = input[end]
                    if character.isWhitespace || character == "<" || character == ">" ||
                        character == "\"" || character == "'" {
                        break
                    }
                    end = input.index(after: end)
                }
                ranges.append(index..<end)
                index = end
            } else {
                index = input.index(after: index)
            }
        }
        return ranges
    }

    private static func hasASCIIPrefix(_ prefix: String, in input: String, at start: String.Index) -> Bool {
        var index = start
        for expected in prefix.utf8 {
            guard index < input.endIndex,
                  let scalar = String(input[index]).unicodeScalars.only,
                  scalar.value < 128,
                  asciiFold(scalar.value) == asciiFold(UInt32(expected)) else {
                return false
            }
            index = input.index(after: index)
        }
        return true
    }

    private static func runLength(
        of marker: Character,
        from start: String.Index,
        until end: String.Index,
        in input: String
    ) -> Int {
        var index = start
        var count = 0
        while index < end, input[index] == marker {
            count += 1
            index = input.index(after: index)
        }
        return count
    }
}

private extension Array where Element == UInt32 {
    subscript(safe index: Int) -> UInt32? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String.UnicodeScalarView {
    var only: Unicode.Scalar? {
        count == 1 ? first : nil
    }
}
