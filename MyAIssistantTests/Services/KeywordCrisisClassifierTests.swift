import XCTest
@testable import MyAIssistant

/// Zero prior coverage on the actual crisis-detection logic (only
/// `NudgeEngine`'s safety-precheck *gating* was tested, with a mocked
/// classifier — never `KeywordCrisisClassifier.evaluate` itself). Per the
/// class's own doc comment, false negatives here mean "a coach message
/// arrives during a crisis," so the matching logic deserves direct tests.
final class KeywordCrisisClassifierTests: XCTestCase {
    private let classifier = KeywordCrisisClassifier()

    // MARK: - Safe inputs

    func testEmptyStringIsSafe() {
        XCTAssertEqual(classifier.evaluate(""), .safe)
    }

    func testOrdinaryTextIsSafe() {
        let result = classifier.evaluate("Had a good run today, feeling tired but happy.")
        XCTAssertFalse(result.isCrisis)
        XCTAssertTrue(result.matchedTerms.isEmpty)
    }

    func testSadnessAndBurnoutLanguageIsNotFlagged() {
        // Explicitly out of scope per the class's doc comment.
        let texts = [
            "I'm so tired of everything lately.",
            "feeling really down and burnt out this week",
            "I'm frustrated and exhausted",
        ]
        for text in texts {
            XCTAssertFalse(classifier.evaluate(text).isCrisis, "false positive on: \(text)")
        }
    }

    // MARK: - Multi-word phrase matches

    func testMultiWordPhraseMatchesCaseInsensitively() {
        let result = classifier.evaluate("Sometimes I think I want to KILL MYSELF.")
        XCTAssertTrue(result.isCrisis)
        XCTAssertTrue(result.matchedTerms.contains("kill myself"))
    }

    func testMultiWordPhraseMatchesAsSubstringMidSentence() {
        let result = classifier.evaluate("honestly i just want to end it all right now")
        XCTAssertTrue(result.isCrisis)
        XCTAssertTrue(result.matchedTerms.contains("end it all"))
    }

    // MARK: - Single-word boundary protection (Q1-BUG-36 regression)

    func testSingleWordDoesNotMatchInsideALongerWord() {
        // "suicide" must not match "suicideprevention" or "skill" vs "kill".
        let result = classifier.evaluate("I volunteer at a suicideprevention hotline and I'm building a new skill.")
        XCTAssertFalse(result.isCrisis, "matched: \(result.matchedTerms)")
    }

    func testSingleWordMatchesAsAStandaloneWord() {
        let result = classifier.evaluate("I've been having suicidal thoughts lately.")
        XCTAssertTrue(result.isCrisis)
        XCTAssertTrue(result.matchedTerms.contains("suicidal"))
    }

    func testSingleWordMatchesAtSentenceBoundaryPunctuation() {
        let result = classifier.evaluate("suicide. that's the word I keep thinking about.")
        XCTAssertTrue(result.isCrisis)
        XCTAssertTrue(result.matchedTerms.contains("suicide"))
    }

    // MARK: - Multiple matches

    func testMultipleDistinctPhrasesAreAllReported() {
        let result = classifier.evaluate("I want to die, there's no reason to live anymore.")
        XCTAssertTrue(result.isCrisis)
        XCTAssertTrue(result.matchedTerms.contains("want to die"))
        XCTAssertTrue(result.matchedTerms.contains("no reason to live"))
        XCTAssertEqual(result.matchedTerms.count, 2)
    }

    // MARK: - Custom pattern list (DI seam used by CoreML swap-in / tests)

    func testCustomPatternListOverridesDefaults() {
        let custom = KeywordCrisisClassifier(patterns: ["banana emergency"])
        XCTAssertFalse(custom.evaluate("I want to kill myself").isCrisis, "default phrase should not match a custom list")
        XCTAssertTrue(custom.evaluate("this is a banana emergency").isCrisis)
    }

    func testCustomPatternsAreLowercasedAtInit() {
        let custom = KeywordCrisisClassifier(patterns: ["BANANA EMERGENCY"])
        XCTAssertTrue(custom.evaluate("banana emergency today").isCrisis)
    }

    // MARK: - CrisisEvaluation equality / .safe

    func testSafeStaticEqualsEmptyEvaluation() {
        XCTAssertEqual(CrisisEvaluation.safe, CrisisEvaluation(isCrisis: false, matchedTerms: []))
    }
}
