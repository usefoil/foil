import Foundation

struct LocalCorrectionRule: Codable, Equatable, Sendable {
    let id: String
    let source: String
    let replacement: String
    let group: String?
    let enabled: Bool
    let caseSensitive: Bool
    let matchPunctuationVariants: Bool
    let suppressesGlobal: Bool

    init(
        id: String,
        source: String,
        replacement: String,
        group: String?,
        enabled: Bool,
        caseSensitive: Bool,
        matchPunctuationVariants: Bool = false,
        suppressesGlobal: Bool = false
    ) {
        self.id = id
        self.source = source
        self.replacement = replacement
        self.group = group
        self.enabled = enabled
        self.caseSensitive = caseSensitive
        self.matchPunctuationVariants = matchPunctuationVariants
        self.suppressesGlobal = suppressesGlobal
    }

    enum CodingKeys: String, CodingKey {
        case id, source, replacement, group, enabled
        case caseSensitive = "case_sensitive"
        case matchPunctuationVariants = "match_punctuation_variants"
        case suppressesGlobal = "suppresses_global"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let encodedSuppression = try container.decodeIfPresent(Bool.self, forKey: .suppressesGlobal) ?? false
        self.init(
            id: id,
            source: try container.decode(String.self, forKey: .source),
            replacement: try container.decode(String.self, forKey: .replacement),
            group: try container.decodeIfPresent(String.self, forKey: .group),
            enabled: try container.decode(Bool.self, forKey: .enabled),
            caseSensitive: try container.decode(Bool.self, forKey: .caseSensitive),
            matchPunctuationVariants: try container.decodeIfPresent(Bool.self, forKey: .matchPunctuationVariants) ?? false,
            suppressesGlobal: id.hasPrefix("suppression:") || encodedSuppression
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(source, forKey: .source)
        try container.encode(replacement, forKey: .replacement)
        try container.encodeIfPresent(group, forKey: .group)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(caseSensitive, forKey: .caseSensitive)
        if matchPunctuationVariants {
            try container.encode(true, forKey: .matchPunctuationVariants)
        }
        if suppressesGlobal {
            try container.encode(true, forKey: .suppressesGlobal)
        }
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
    case invalidSuppression(String)
    case invalidPunctuationVariantSource(String)

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
        case .invalidSuppression(let id):
            "A global rule cannot suppress itself: \(id)"
        case .invalidPunctuationVariantSource(let id):
            "Local correction rule \(id) needs two words separated by spacing or punctuation for punctuation variants"
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
        let suppressesGlobal: Bool
    }

    fileprivate struct TrieNode: Sendable {
        var children: [UInt32: Int] = [:]
        var terminalRuleIndexes: [Int] = []
    }

    fileprivate let rules: [Rule]
    fileprivate let sensitiveTrie: [TrieNode]
    fileprivate let insensitiveTrie: [TrieNode]
    fileprivate let punctuationSensitiveTrie: [TrieNode]
    fileprivate let punctuationInsensitiveTrie: [TrieNode]
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
    private static let punctuationSeparator: UInt32 = UInt32.max

    private struct AliasKey: Hashable {
        let group: String?
        let foldedSource: [UInt32]
    }

    private struct PriorAlias {
        let id: String
        let normalizedSource: [UInt32]
        let comparableSource: [UInt32]
        let caseSensitive: Bool
        let matchPunctuationVariants: Bool
    }

    static func compile(_ rules: [LocalCorrectionRule]) throws -> CompiledLocalCorrections {
        try validate(rules)

        var compiledRules: [CompiledLocalCorrections.Rule] = []
        var sensitiveTrie = [CompiledLocalCorrections.TrieNode()]
        var insensitiveTrie = [CompiledLocalCorrections.TrieNode()]
        var punctuationSensitiveTrie = [CompiledLocalCorrections.TrieNode()]
        var punctuationInsensitiveTrie = [CompiledLocalCorrections.TrieNode()]

        for rule in rules where rule.enabled {
            let scalars = normalizedScalars(rule.source)
            let matchingScalars = rule.matchPunctuationVariants
                ? punctuationVariantScalars(scalars)!
                : scalars
            let compiledIndex = compiledRules.count
            compiledRules.append(
                .init(
                    id: rule.id,
                    replacement: rule.replacement,
                    replacementUTF8: Array(rule.replacement.utf8),
                    group: rule.group,
                    scalarCount: matchingScalars.count,
                    suppressesGlobal: rule.suppressesGlobal
                )
            )
            if rule.matchPunctuationVariants && rule.caseSensitive {
                insert(matchingScalars, ruleIndex: compiledIndex, into: &punctuationSensitiveTrie)
            } else if rule.matchPunctuationVariants {
                insert(matchingScalars.map(asciiFold), ruleIndex: compiledIndex, into: &punctuationInsensitiveTrie)
            } else if rule.caseSensitive {
                insert(scalars, ruleIndex: compiledIndex, into: &sensitiveTrie)
            } else {
                insert(scalars.map(asciiFold), ruleIndex: compiledIndex, into: &insensitiveTrie)
            }
        }

        return CompiledLocalCorrections(
            rules: compiledRules,
            sensitiveTrie: sensitiveTrie,
            insensitiveTrie: insensitiveTrie,
            punctuationSensitiveTrie: punctuationSensitiveTrie,
            punctuationInsensitiveTrie: punctuationInsensitiveTrie
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
        if compiled.punctuationSensitiveTrie.count == 1,
           compiled.punctuationInsensitiveTrie.count == 1,
           inputUTF8.allSatisfy({ $0 < 128 }) {
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
                if match.rule.suppressesGlobal {
                    output.append(contentsOf: input[originalStart..<originalEnd])
                } else {
                    output.append(match.rule.replacement)
                    replacementCount += 1
                }
                copyStart = originalEnd
                scalarPosition = match.endScalarPosition
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
        let matchedScalarCount: Int
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
            let rule = compiled.rules[replacement.match.ruleIndex]
            if rule.suppressesGlobal {
                output.append(contentsOf: input[replacement.start..<replacement.match.endBytePosition])
            } else {
                output.append(contentsOf: rule.replacementUTF8)
            }
            copyStart = replacement.match.endBytePosition
        }
        output.append(contentsOf: input[copyStart..<input.count])
        return LocalCorrectionResult(
            text: String(decoding: output, as: UTF8.self),
            replacementCount: replacements.filter { !compiled.rules[$0.match.ruleIndex].suppressesGlobal }.count,
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
        if candidateRule.scalarCount != currentRule.scalarCount {
            return candidateRule.scalarCount > currentRule.scalarCount
        }
        let candidateScoped = candidateRule.group == nil ? 0 : 1
        let currentScoped = currentRule.group == nil ? 0 : 1
        if candidateScoped != currentScoped { return candidateScoped > currentScoped }
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
        if compiled.punctuationSensitiveTrie.count > 1 {
            scanTrie(
                compiled.punctuationSensitiveTrie,
                folded: false,
                punctuationVariants: true,
                start: start,
                normalized: normalized,
                activeGroup: activeGroup,
                compiled: compiled,
                protectedRanges: protectedRanges,
                best: &best
            )
        }
        if compiled.punctuationInsensitiveTrie.count > 1 {
            scanTrie(
                compiled.punctuationInsensitiveTrie,
                folded: true,
                punctuationVariants: true,
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
        punctuationVariants: Bool = false,
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
            let inputScalar = normalized.scalars[position]
            let scalar: UInt32
            if punctuationVariants && isPunctuationSeparator(inputScalar) {
                scalar = punctuationSeparator
                repeat {
                    position += 1
                } while position < normalized.scalars.count &&
                    isPunctuationSeparator(normalized.scalars[position])
            } else {
                scalar = folded ? asciiFold(inputScalar) : inputScalar
                position += 1
            }
            guard let nextNode = trie[nodeIndex].children[scalar] else { return }
            nodeIndex = nextNode

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
                let candidate = Match(
                    rule: rule,
                    endScalarPosition: position,
                    matchedScalarCount: position - start
                )
                if isPreferred(candidate, over: best) {
                    best = candidate
                }
            }
        }
    }

    private static func isPreferred(_ candidate: Match, over current: Match?) -> Bool {
        guard let current else { return true }
        if candidate.matchedScalarCount != current.matchedScalarCount {
            return candidate.matchedScalarCount > current.matchedScalarCount
        }
        let candidateScoped = candidate.rule.group == nil ? 0 : 1
        let currentScoped = current.rule.group == nil ? 0 : 1
        if candidateScoped != currentScoped { return candidateScoped > currentScoped }
        return candidate.rule.id < current.rule.id
    }

    private static func validate(_ rules: [LocalCorrectionRule]) throws {
        let enabledCount = rules.lazy.filter(\.enabled).count
        guard enabledCount <= maximumEnabledRules else {
            throw LocalCorrectionValidationError.tooManyEnabledRules(enabledCount)
        }

        var ids = Set<String>()
        var priorByAlias: [AliasKey: [PriorAlias]] = [:]
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
            guard !rule.suppressesGlobal || rule.group != nil else {
                throw LocalCorrectionValidationError.invalidSuppression(rule.id)
            }
            guard rule.source.unicodeScalars.count <= maximumPhraseScalars,
                  rule.replacement.unicodeScalars.count <= maximumPhraseScalars else {
                throw LocalCorrectionValidationError.phraseTooLong(rule.id)
            }
            let normalizedSource = normalizedScalars(rule.source)
            let variantSource = punctuationVariantScalars(normalizedSource)
            if rule.matchPunctuationVariants && variantSource == nil {
                throw LocalCorrectionValidationError.invalidPunctuationVariantSource(rule.id)
            }
            let comparableSource = variantSource ?? normalizedSource
            let key = AliasKey(group: rule.group, foldedSource: comparableSource.map(asciiFold))
            for previous in priorByAlias[key] ?? [] {
                let prior = previous.matchPunctuationVariants || rule.matchPunctuationVariants
                    ? previous.comparableSource : previous.normalizedSource
                let current = previous.matchPunctuationVariants || rule.matchPunctuationVariants
                    ? comparableSource : normalizedSource
                let overlaps = previous.caseSensitive && rule.caseSensitive
                    ? prior == current : prior.map(asciiFold) == current.map(asciiFold)
                if overlaps {
                    throw LocalCorrectionValidationError.ambiguousAlias(previous.id, rule.id)
                }
            }
            priorByAlias[key, default: []].append(PriorAlias(
                id: rule.id,
                normalizedSource: normalizedSource,
                comparableSource: comparableSource,
                caseSensitive: rule.caseSensitive,
                matchPunctuationVariants: rule.matchPunctuationVariants
            ))
        }
    }

    static func aliasesOverlap(
        _ first: String,
        caseSensitive firstCaseSensitive: Bool,
        matchPunctuationVariants firstPunctuationVariants: Bool = false,
        _ second: String,
        caseSensitive secondCaseSensitive: Bool,
        matchPunctuationVariants secondPunctuationVariants: Bool = false
    ) -> Bool {
        let firstNormalized = normalizedScalars(first)
        let secondNormalized = normalizedScalars(second)
        let firstComparable = firstPunctuationVariants || secondPunctuationVariants
            ? (punctuationVariantScalars(firstNormalized) ?? firstNormalized)
            : firstNormalized
        let secondComparable = firstPunctuationVariants || secondPunctuationVariants
            ? (punctuationVariantScalars(secondNormalized) ?? secondNormalized)
            : secondNormalized
        if firstCaseSensitive && secondCaseSensitive {
            return firstComparable == secondComparable
        }
        return firstComparable.map(asciiFold) == secondComparable.map(asciiFold)
    }

    static func supportsPunctuationVariants(_ source: String) -> Bool {
        punctuationVariantScalars(normalizedScalars(source)) != nil
    }

    private static func punctuationVariantScalars(_ scalars: [UInt32]) -> [UInt32]? {
        guard let first = scalars.first, let last = scalars.last,
              isBoundaryBlocking(first), isBoundaryBlocking(last) else { return nil }
        var result: [UInt32] = []
        result.reserveCapacity(scalars.count)
        var sawSeparator = false
        for scalar in scalars {
            if isPunctuationSeparator(scalar) {
                if result.last != punctuationSeparator {
                    result.append(punctuationSeparator)
                    sawSeparator = true
                }
            } else if isBoundaryBlocking(scalar) {
                result.append(scalar)
            } else {
                return nil
            }
        }
        return sawSeparator ? result : nil
    }

    private static func isPunctuationSeparator(_ value: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(value) else { return false }
        if CharacterSet.whitespacesAndNewlines.contains(scalar) { return true }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation:
            return true
        default:
            return false
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
