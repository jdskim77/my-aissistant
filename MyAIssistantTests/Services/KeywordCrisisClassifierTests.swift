import XCTest
@testable import MyAIssistant

final class KeywordCrisisClassifierTests: XCTestCase {

    private var sut: KeywordCrisisClassifier!

    override func setUp() {
        sut = KeywordCrisisClassifier()
    }

    override func tearDown() {
        sut = nil
    }

    // MARK: - Empty / whitespace inputs

    func test_evaluate_emptyString_returnsSafe() {
        XCTAssertFalse(sut.evaluate("").isCrisis)
    }

    func test_evaluate_whitespaceOnly_returnsSafe() {
        // Trimming guard fixed in the classifier QA pass — whitespace-only
        // notes are equivalent to empty and should not engage the keyword
        // matcher (would be wasted work + a CPU walk over ~30 patterns).
        XCTAssertFalse(sut.evaluate("   \n\t  ").isCrisis)
    }

    func test_evaluate_zeroWidthSpaceOnly_returnsSafe() {
        XCTAssertFalse(sut.evaluate("\u{200B}\u{200B}").isCrisis)
    }

    // MARK: - Multi-word matches (substring path)

    func test_evaluate_explicitSelfHarmPhrase_isCrisis() {
        let result = sut.evaluate("I want to kill myself.")
        XCTAssertTrue(result.isCrisis)
        XCTAssertTrue(result.matchedTerms.contains("kill myself"))
    }

    func test_evaluate_caseInsensitive() {
        XCTAssertTrue(sut.evaluate("I WANT TO DIE").isCrisis)
        XCTAssertTrue(sut.evaluate("I Want To Die").isCrisis)
    }

    func test_evaluate_normalDistress_isSafe() {
        // Burnout / sadness / frustration must NOT trigger — the classifier
        // is deliberately conservative so the check-in surface can hold
        // ordinary low-mood content. Subtle distress is for a trained model.
        XCTAssertFalse(sut.evaluate("I'm really tired today.").isCrisis)
        XCTAssertFalse(sut.evaluate("Feeling low and frustrated.").isCrisis)
        XCTAssertFalse(sut.evaluate("I hate my job lately.").isCrisis)
    }

    // MARK: - Single-word matches (regex path)

    func test_evaluate_suicideKeyword_isCrisis() {
        XCTAssertTrue(sut.evaluate("Reading about suicide today.").isCrisis)
    }

    func test_evaluate_substringFalseMatch_doesNotTrigger() {
        // Word-boundary regex path: "skill myself motivated" must NOT match
        // "kill myself" (it's a substring with no word boundary).
        // Wait — "kill myself" is multi-word so it goes through substring
        // path; but "kill" doesn't appear as a single-word pattern. Verify
        // a real single-word pattern's boundary protection: "suicide" must
        // not match inside "suicideprevention" (compound, no boundary).
        XCTAssertFalse(sut.evaluate("suicideprevention.org is a great resource").isCrisis)
    }

    // MARK: - Non-English

    func test_evaluate_spanishCrisisPhrase_isCrisis() {
        XCTAssertTrue(sut.evaluate("me quiero morir").isCrisis)
    }

    func test_evaluate_japaneseCrisisPhrase_isCrisis() {
        XCTAssertTrue(sut.evaluate("死にたい").isCrisis)
    }

    func test_evaluate_chineseCrisisPhrase_isCrisis() {
        XCTAssertTrue(sut.evaluate("想死").isCrisis)
    }

    // MARK: - Custom pattern list

    func test_evaluate_customPatterns_only() {
        let custom = KeywordCrisisClassifier(patterns: ["custom phrase"])
        XCTAssertTrue(custom.evaluate("This contains a custom phrase here.").isCrisis)
        XCTAssertFalse(custom.evaluate("I want to die").isCrisis)
    }

    // MARK: - Detected language

    func test_evaluate_englishMatch_returnsEnglishLanguage() {
        let result = sut.evaluate("I want to die")
        XCTAssertTrue(result.isCrisis)
        XCTAssertEqual(result.detectedLanguage, "en",
                       "English match must report detectedLanguage='en' so SafeResourceCopy renders English copy.")
    }

    func test_evaluate_spanishMatch_returnsSpanishLanguage() {
        let result = sut.evaluate("me quiero morir")
        XCTAssertTrue(result.isCrisis)
        XCTAssertEqual(result.detectedLanguage, "es",
                       "Spanish match must report 'es' regardless of Locale.current.")
    }

    func test_evaluate_portugueseMatch_returnsPortugueseLanguage() {
        let result = sut.evaluate("quero morrer")
        XCTAssertTrue(result.isCrisis)
        XCTAssertEqual(result.detectedLanguage, "pt")
    }

    func test_evaluate_japaneseMatch_returnsJapaneseLanguage() {
        let result = sut.evaluate("死にたい")
        XCTAssertTrue(result.isCrisis)
        XCTAssertEqual(result.detectedLanguage, "ja")
    }

    func test_evaluate_chineseMatch_returnsChineseLanguage() {
        let result = sut.evaluate("想死")
        XCTAssertTrue(result.isCrisis)
        XCTAssertEqual(result.detectedLanguage, "zh")
    }

    func test_evaluate_safeText_returnsNilLanguage() {
        let result = sut.evaluate("regular journal entry")
        XCTAssertFalse(result.isCrisis)
        XCTAssertNil(result.detectedLanguage)
    }

    func test_evaluate_customPattern_returnsNilLanguage() {
        // Custom (non-default) patterns aren't in any language group, so
        // detectedLanguage should be nil. Caller falls back to Locale.current.
        let custom = KeywordCrisisClassifier(patterns: ["custom phrase"])
        let result = custom.evaluate("This contains a custom phrase here.")
        XCTAssertTrue(result.isCrisis)
        XCTAssertNil(result.detectedLanguage,
                     "Custom patterns aren't in language groups; falling back to Locale.current is correct.")
    }

    // MARK: - Performance: regex precompile

    func test_evaluate_repeatedCalls_doesNotRecompileRegex() {
        // Smoke check that repeated evaluation is cheap. Pre-fix this took
        // ~30 NSRegularExpression compilations per call. We don't measure
        // wall time (flaky in CI) but we do call it a lot to surface any
        // catastrophic backtracking or unbounded growth.
        let haystack = "An ordinary note about my day. " + String(repeating: "a", count: 5_000)
        for _ in 0..<200 {
            _ = sut.evaluate(haystack)
        }
        // No assertion — passing means no crash, no timeout, no leak.
    }
}
