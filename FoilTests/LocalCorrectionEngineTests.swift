import XCTest
@testable import Foil

final class LocalCorrectionEngineTests: XCTestCase {
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

    func testScopedRuleWinsOverLongerGlobalRule() throws {
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

        XCTAssertEqual(result.text, "Supabase auth")
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
        caseSensitive: Bool = false
    ) -> LocalCorrectionRule {
        LocalCorrectionRule(
            id: id,
            source: source,
            replacement: replacement,
            group: group,
            enabled: enabled,
            caseSensitive: caseSensitive
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
