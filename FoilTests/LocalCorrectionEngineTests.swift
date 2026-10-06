import XCTest
@testable import Foil

final class LocalCorrectionEngineTests: XCTestCase {
    func testOptInPunctuationVariantsReplaceOnlyTheInternalSeparator() throws {
        let compiled = try LocalCorrectionEngine.compile([
            rule(id: "supabase", source: "super base", replacement: "Supabase", matchPunctuationVariants: true)
        ])
        let input = "super base, super-base; super, base! super—base? superbase"
        let result = LocalCorrectionEngine.correct(input, activeGroup: "agents", enabled: true, compiled: compiled)
        XCTAssertEqual(result.text, "Supabase, Supabase; Supabase! Supabase? superbase")
        XCTAssertEqual(result.replacementCount, 4)
    }

    func testPunctuationVariantsRemainExactByDefaultAndSkipProtectedText() throws {
        let exact = try LocalCorrectionEngine.compile([
            rule(id: "exact", source: "super base", replacement: "Supabase")
        ])
        XCTAssertEqual(
            LocalCorrectionEngine.correct("super-base, super base", activeGroup: "agents", enabled: true, compiled: exact).text,
            "super-base, Supabase"
        )

        let variants = try LocalCorrectionEngine.compile([
            rule(id: "variants", source: "super base", replacement: "Supabase", matchPunctuationVariants: true)
        ])
        XCTAssertEqual(
            LocalCorrectionEngine.correct("`super-base` https://host/super-base then super-base", activeGroup: "agents", enabled: true, compiled: variants).text,
            "`super-base` https://host/super-base then Supabase"
        )
    }

    func testPunctuationVariantsDoNotRewriteBarePathsOrIdentifiers() throws {
        let compiled = try LocalCorrectionEngine.compile([
            rule(id: "variants", source: "super base", replacement: "Supabase", matchPunctuationVariants: true)
        ])
        let input = "super-base /super-base super-base/ path/super-base/config super_base super/base super\\base super@base super.base@example.com foo@super-base"
        XCTAssertEqual(
            LocalCorrectionEngine.correct(input, activeGroup: "agents", enabled: true, compiled: compiled).text,
            "Supabase /super-base super-base/ path/super-base/config super_base super/base super\\base super@base super.base@example.com foo@super-base"
        )
    }

    func testScopedPunctuationVariantOverridesGlobalMatchAndSuppression() throws {
        let compiled = try LocalCorrectionEngine.compile([
            rule(id: "global", source: "super base", replacement: "Global", group: nil, matchPunctuationVariants: true),
            rule(id: "scoped", source: "super base", replacement: "Scoped", group: "agents", matchPunctuationVariants: true)
        ])
        XCTAssertEqual(LocalCorrectionEngine.correct("super-base", activeGroup: "agents", enabled: true, compiled: compiled).text, "Scoped")
        XCTAssertEqual(LocalCorrectionEngine.correct("super-base", activeGroup: "other", enabled: true, compiled: compiled).text, "Global")

        let suppressed = try LocalCorrectionEngine.compile([
            rule(id: "global", source: "super base", replacement: "Global", group: nil, matchPunctuationVariants: true),
            rule(id: "suppression:global:agents", source: "super base", replacement: "super base",
                 group: "agents", matchPunctuationVariants: true, suppressesGlobal: true)
        ])
        XCTAssertEqual(LocalCorrectionEngine.correct("super-base", activeGroup: "agents", enabled: true, compiled: suppressed).text, "super-base")

        let exactGlobal = try LocalCorrectionEngine.compile([
            rule(id: "global", source: "super--base", replacement: "Global", group: nil),
            rule(id: "scoped", source: "super base", replacement: "Scoped", group: "agents", matchPunctuationVariants: true)
        ])
        XCTAssertEqual(LocalCorrectionEngine.correct("super--base", activeGroup: "agents", enabled: true, compiled: exactGlobal).text, "Scoped")
    }

    func testPunctuationVariantValidationRejectsOverlappingAliases() throws {
        XCTAssertThrowsError(try LocalCorrectionEngine.compile([
            rule(id: "a", source: "super base", replacement: "A", matchPunctuationVariants: true),
            rule(id: "b", source: "super-base", replacement: "B")
        ])) { error in
            XCTAssertEqual(error as? LocalCorrectionValidationError, .ambiguousAlias("a", "b"))
        }
        XCTAssertThrowsError(try LocalCorrectionEngine.compile([
            rule(id: "bad", source: "Supabase", replacement: "Good", matchPunctuationVariants: true)
        ])) { error in
            XCTAssertEqual(error as? LocalCorrectionValidationError, .invalidPunctuationVariantSource("bad"))
        }
        XCTAssertThrowsError(try LocalCorrectionEngine.compile([
            rule(id: "path", source: "super/base", replacement: "Supabase", matchPunctuationVariants: true)
        ])) { error in
            XCTAssertEqual(error as? LocalCorrectionValidationError, .invalidPunctuationVariantSource("path"))
        }
    }

    func testCanonicalMatchPreservesUntouchedOriginalBytes() throws {
        let input = "Cafe\u{301} with cafe\u{301}"
        let compiled = try LocalCorrectionEngine.compile([
            rule(id: "coffee", source: "café", replacement: "Coffee")
        ])

        let result = LocalCorrectionEngine.correct(
            input,
            activeGroup: "agents",
            enabled: true,
            compiled: compiled
        )

        XCTAssertEqual(Array(result.text.utf8), Array("Coffee with Coffee".utf8))
        XCTAssertEqual(result.replacementCount, 2)
        XCTAssertNil(result.fallbackReason)
    }

    func testLongerGlobalPhraseWinsOverShorterScopedPhrase() throws {
        let compiled = try LocalCorrectionEngine.compile([
            rule(id: "global", source: "super base auth", replacement: "GLOBAL", group: nil),
            rule(id: "scoped", source: "super base", replacement: "Supabase", group: "agents")
        ])

        let result = LocalCorrectionEngine.correct(
            "super base auth",
            activeGroup: "agents",
            enabled: true,
            compiled: compiled
        )

        XCTAssertEqual(result.text, "GLOBAL")
    }

    func testScopedRuleOverridesSameGlobalPhraseOnlyInItsGroup() throws {
        let compiled = try LocalCorrectionEngine.compile([
            rule(id: "global", source: "super base", replacement: "Global", group: nil),
            rule(id: "scoped", source: "super base", replacement: "Supabase", group: "agents")
        ])

        XCTAssertEqual(
            LocalCorrectionEngine.correct("super base", activeGroup: "agents", enabled: true, compiled: compiled).text,
            "Supabase"
        )
        XCTAssertEqual(
            LocalCorrectionEngine.correct("super base", activeGroup: "other", enabled: true, compiled: compiled).text,
            "Global"
        )
    }

    func testGroupSuppressionLeavesExactGlobalPhraseUntouched() throws {
        let compiled = try LocalCorrectionEngine.compile([
            rule(id: "global", source: "super base", replacement: "Supabase", group: nil),
            rule(id: "exception", source: "super base", replacement: "super base",
                 group: "agents", suppressesGlobal: true)
        ])

        let protected = LocalCorrectionEngine.correct(
            "super base and café", activeGroup: "agents", enabled: true, compiled: compiled
        )
        XCTAssertEqual(protected.text, "super base and café")
        XCTAssertEqual(protected.replacementCount, 0)
        XCTAssertEqual(
            LocalCorrectionEngine.correct("super base", activeGroup: "other", enabled: true, compiled: compiled).text,
            "Supabase"
        )
    }

    func testSuppressionDoesNotMaskLongerDistinctGlobalPhrase() throws {
        let compiled = try LocalCorrectionEngine.compile([
            rule(id: "global", source: "super base auth", replacement: "AUTH", group: nil),
            rule(id: "exception", source: "super base", replacement: "super base",
                 group: "agents", suppressesGlobal: true)
        ])
        XCTAssertEqual(
            LocalCorrectionEngine.correct("super base auth", activeGroup: "agents", enabled: true, compiled: compiled).text,
            "AUTH"
        )
    }

    func testSuppressionSurvivesOlderRuleEncodingWithoutNewFlag() throws {
        let payload = #"{"id":"suppression:11111111-1111-1111-1111-111111111111:agents","source":"super base","replacement":"super base","group":"agents","enabled":true,"case_sensitive":false}"#
        let rule = try JSONDecoder().decode(LocalCorrectionRule.self, from: Data(payload.utf8))
        XCTAssertTrue(rule.suppressesGlobal)
        XCTAssertFalse(rule.matchPunctuationVariants)
        let compiled = try LocalCorrectionEngine.compile([
            self.rule(id: "global", source: "super base", replacement: "Supabase", group: nil), rule
        ])
        XCTAssertEqual(
            LocalCorrectionEngine.correct("super base", activeGroup: "agents", enabled: true, compiled: compiled).text,
            "super base"
        )
    }

    func testPunctuationVariantFlagPersistsWithoutChangingLegacyRuleEncoding() throws {
        let exact = rule(id: "exact", source: "super base", replacement: "Supabase")
        let exactJSON = String(decoding: try JSONEncoder().encode(exact), as: UTF8.self)
        XCTAssertFalse(exactJSON.contains("match_punctuation_variants"))
        let variant = rule(id: "variant", source: "super base", replacement: "Supabase", matchPunctuationVariants: true)
        let stored = try JSONEncoder().encode(variant)
        XCTAssertTrue(String(decoding: stored, as: UTF8.self).contains("\"match_punctuation_variants\":true"))
        XCTAssertEqual(try JSONDecoder().decode(LocalCorrectionRule.self, from: stored), variant)
    }

    func testProtectedCodeAndURLRemainUntouched() throws {
        let compiled = try LocalCorrectionEngine.compile([
            rule(id: "codex", source: "codecs", replacement: "Codex")
        ])

        let result = LocalCorrectionEngine.correct(
            "`codecs` https://host/codecs then codecs",
            activeGroup: "agents",
            enabled: true,
            compiled: compiled
        )

        XCTAssertEqual(result.text, "`codecs` https://host/codecs then Codex")
    }

    func testOversizeInputFallsBackWithoutPartialReplacement() throws {
        let compiled = try LocalCorrectionEngine.compile([
            rule(id: "a", source: "a", replacement: "b")
        ])
        let input = String(repeating: "a", count: LocalCorrectionEngine.maximumInputBytes + 1)

        let result = LocalCorrectionEngine.correct(
            input,
            activeGroup: "agents",
            enabled: true,
            compiled: compiled
        )

        XCTAssertEqual(result.text, input)
        XCTAssertEqual(result.replacementCount, 0)
        XCTAssertEqual(result.fallbackReason, .inputTooLarge)
    }

    func testOversizeInputWithoutApplicableRuleIsNotAnEngineFallback() throws {
        let input = String(repeating: "a", count: LocalCorrectionEngine.maximumInputBytes + 1)
        let empty = try LocalCorrectionEngine.compile([])
        let otherScope = try LocalCorrectionEngine.compile([
            rule(id: "other", source: "a", replacement: "b", group: "other")
        ])

        for compiled in [empty, otherScope] {
            let result = LocalCorrectionEngine.correct(
                input,
                activeGroup: "agents",
                enabled: true,
                compiled: compiled
            )

            XCTAssertEqual(result.text, input)
            XCTAssertEqual(result.replacementCount, 0)
            XCTAssertNil(result.fallbackReason)
        }
    }

    func testDisabledOperationReturnsOriginalBytes() throws {
        let input = "Cafe\u{301} uses super base"
        let compiled = try LocalCorrectionEngine.compile([
            rule(id: "supabase", source: "super base", replacement: "Supabase")
        ])

        let result = LocalCorrectionEngine.correct(
            input,
            activeGroup: "agents",
            enabled: false,
            compiled: compiled
        )

        XCTAssertEqual(Array(result.text.utf8), Array(input.utf8))
        XCTAssertEqual(result.fallbackReason, .processingDisabled)
    }

    func testValidationRejectsAmbiguousAliasEvenWhenOneRuleIsDisabled() {
        XCTAssertThrowsError(
            try LocalCorrectionEngine.compile([
                rule(id: "one", source: "SUPER BASE", replacement: "First", enabled: false, caseSensitive: true),
                rule(id: "two", source: "super base", replacement: "Second", caseSensitive: false)
            ])
        ) { error in
            XCTAssertEqual(error as? LocalCorrectionValidationError, .ambiguousAlias("one", "two"))
        }
    }

    func testValidationAllowsDistinctCaseSensitiveAliasesButRejectsInsensitiveOverlap() throws {
        let sensitive = [
            rule(id: "upper", source: "Codex", replacement: "Upper", caseSensitive: true),
            rule(id: "lower", source: "codex", replacement: "Lower", caseSensitive: true)
        ]
        XCTAssertNoThrow(try LocalCorrectionEngine.compile(sensitive))
        XCTAssertThrowsError(try LocalCorrectionEngine.compile(sensitive + [
            rule(id: "folded", source: "CODEX", replacement: "Folded", caseSensitive: false)
        ])) { error in
            XCTAssertEqual(error as? LocalCorrectionValidationError, .ambiguousAlias("upper", "folded"))
        }
    }

    func testValidationCountsOnlyEnabledRulesTowardLimit() throws {
        let disabled = (0...LocalCorrectionEngine.maximumEnabledRules).map { index in
            rule(id: "disabled-\(index)", source: "disabled-\(index)", replacement: "x", enabled: false)
        }
        XCTAssertNoThrow(try LocalCorrectionEngine.compile(disabled))

        let enabled = (0...LocalCorrectionEngine.maximumEnabledRules).map { index in
            rule(id: "enabled-\(index)", source: "enabled-\(index)", replacement: "x")
        }
        XCTAssertThrowsError(try LocalCorrectionEngine.compile(enabled)) { error in
            XCTAssertEqual(
                error as? LocalCorrectionValidationError,
                .tooManyEnabledRules(LocalCorrectionEngine.maximumEnabledRules + 1)
            )
        }
    }

    func testValidationCountsConfiguredSourceScalarsBeforeNormalization() {
        let decomposedSource = String(repeating: "e\u{301}", count: 129)

        XCTAssertEqual(decomposedSource.unicodeScalars.count, 258)
        XCTAssertThrowsError(
            try LocalCorrectionEngine.compile([
                rule(id: "oversize-decomposed", source: decomposedSource, replacement: "x")
            ])
        ) { error in
            XCTAssertEqual(
                error as? LocalCorrectionValidationError,
                .phraseTooLong("oversize-decomposed")
            )
        }
    }

    func testCRLFSourceRemainsDistinctAndMatchesAsOneCharacter() throws {
        let compiled = try LocalCorrectionEngine.compile([
            rule(id: "crlf", source: "\r\nnext", replacement: "line"),
            rule(id: "lf", source: "\nnext", replacement: "wrong")
        ])

        let ascii = LocalCorrectionEngine.correct(
            "before \r\nnext!",
            activeGroup: "agents",
            enabled: true,
            compiled: compiled
        )
        let unicode = LocalCorrectionEngine.correct(
            "café before \r\nnext!",
            activeGroup: "agents",
            enabled: true,
            compiled: compiled
        )
        let loneLF = LocalCorrectionEngine.correct(
            "before \nnext!",
            activeGroup: "agents",
            enabled: true,
            compiled: compiled
        )

        XCTAssertEqual(ascii.text, "before line!")
        XCTAssertEqual(ascii.replacementCount, 1)
        XCTAssertEqual(unicode.text, "café before line!")
        XCTAssertEqual(unicode.replacementCount, 1)
        XCTAssertEqual(loneLF.text, "before wrong!")
        XCTAssertEqual(loneLF.replacementCount, 1)
    }

    func testCRLFFenceClosesBeforeFollowingProse() throws {
        let compiled = try LocalCorrectionEngine.compile([
            rule(id: "codex", source: "codecs", replacement: "Codex")
        ])

        let result = LocalCorrectionEngine.correct(
            "```\r\ncodecs\r\n```\r\ncodecs",
            activeGroup: "agents",
            enabled: true,
            compiled: compiled
        )

        XCTAssertEqual(result.text, "```\r\ncodecs\r\n```\r\nCodex")
        XCTAssertEqual(result.replacementCount, 1)
    }

    func testTenThousandSeededCasesAreDeterministicScopedAndByteExact() throws {
        var generator = SeededGenerator(seed: 20_260_914)
        for index in 0..<10_000 {
            let source = "alias\(index)"
            let spoken = generator.next() & 1 == 0 ? source : source.uppercased()
            let activeGroup = generator.next() & 1 == 0 ? "agents" : "human"
            let otherGroup = activeGroup == "agents" ? "human" : "agents"
            let prefix = "Cafe\u{301} #\(index): `\(spoken)` https://host/\(source) then "
            let suffix = " ✅\r\n"
            let input = prefix + spoken + suffix
            let expected = prefix + "Term\(index)" + suffix
            let rules = [
                rule(id: "global", source: source, replacement: "GLOBAL", group: nil),
                rule(id: "inactive", source: source, replacement: "WRONG", group: otherGroup),
                rule(id: "selected", source: source, replacement: "Term\(index)", group: activeGroup)
            ]

            let forward = LocalCorrectionEngine.correct(
                input,
                activeGroup: activeGroup,
                enabled: true,
                compiled: try LocalCorrectionEngine.compile(rules)
            )
            let reversed = LocalCorrectionEngine.correct(
                input,
                activeGroup: activeGroup,
                enabled: true,
                compiled: try LocalCorrectionEngine.compile(rules.reversed())
            )

            XCTAssertEqual(Array(forward.text.utf8), Array(expected.utf8), "seeded case \(index)")
            XCTAssertEqual(Array(reversed.text.utf8), Array(expected.utf8), "reordered seeded case \(index)")
            XCTAssertEqual(forward, reversed, "rule order changed seeded case \(index)")
            XCTAssertEqual(forward.replacementCount, 1, "seeded case \(index)")
            XCTAssertLessThanOrEqual(
                forward.text.utf8.count,
                input.utf8.count + "Term\(index)".utf8.count,
                "seeded case \(index) produced unbounded output"
            )
        }
    }

    private func rule(
        id: String,
        source: String,
        replacement: String,
        group: String? = "agents",
        enabled: Bool = true,
        caseSensitive: Bool = false,
        matchPunctuationVariants: Bool = false,
        suppressesGlobal: Bool = false
    ) -> LocalCorrectionRule {
        LocalCorrectionRule(
            id: id,
            source: source,
            replacement: replacement,
            group: group,
            enabled: enabled,
            caseSensitive: caseSensitive,
            matchPunctuationVariants: matchPunctuationVariants,
            suppressesGlobal: suppressesGlobal
        )
    }
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
