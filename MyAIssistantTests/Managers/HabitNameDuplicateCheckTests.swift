import XCTest
@testable import MyAIssistant

final class HabitNameDuplicateCheckTests: XCTestCase {
    func test_normalize_lowercasesAndTrims() {
        XCTAssertEqual(HabitNameDuplicateCheck.normalize("  Morning Run  "), "morning run")
    }

    func test_normalize_stripsPunctuation() {
        XCTAssertEqual(HabitNameDuplicateCheck.normalize("Morning - 10 surf popups"), "morning 10 surf popups")
        XCTAssertEqual(HabitNameDuplicateCheck.normalize("10 Surf popups!"), "10 surf popups")
    }

    func test_normalize_collapsesInternalWhitespace() {
        XCTAssertEqual(HabitNameDuplicateCheck.normalize("Morning   run"), "morning run")
    }

    func test_duplicate_exactCaseInsensitiveMatch_detected() {
        let match = HabitNameDuplicateCheck.duplicate(
            of: "morning run",
            among: [(id: "1", title: "Morning Run"), (id: "2", title: "Evening walk")]
        )
        XCTAssertEqual(match, "Morning Run")
    }

    func test_duplicate_punctuationInsensitiveMatch_detected() {
        let match = HabitNameDuplicateCheck.duplicate(
            of: "10 Surf popups!",
            among: [(id: "1", title: "10 surf popups")]
        )
        XCTAssertEqual(match, "10 surf popups")
    }

    func test_duplicate_noMatch_returnsNil() {
        let match = HabitNameDuplicateCheck.duplicate(
            of: "Meditate",
            among: [(id: "1", title: "Morning Run"), (id: "2", title: "Evening walk")]
        )
        XCTAssertNil(match)
    }

    func test_duplicate_emptyCandidate_returnsNil() {
        let match = HabitNameDuplicateCheck.duplicate(
            of: "   ",
            among: [(id: "1", title: "Morning Run")]
        )
        XCTAssertNil(match)
    }

    func test_duplicate_excludingSelf_doesNotWarnOnUnchangedEdit() {
        let match = HabitNameDuplicateCheck.duplicate(
            of: "Morning Run",
            among: [(id: "1", title: "Morning Run"), (id: "2", title: "Evening walk")],
            excludingID: "1"
        )
        XCTAssertNil(match)
    }

    func test_duplicate_excludingSelf_stillWarnsOnOtherCollision() {
        let match = HabitNameDuplicateCheck.duplicate(
            of: "Evening Walk",
            among: [(id: "1", title: "Morning Run"), (id: "2", title: "Evening walk")],
            excludingID: "1"
        )
        XCTAssertEqual(match, "Evening walk")
    }

    /// The Codex-audit regression case: two *other* habits legitimately
    /// share a name. Excluding by title (the old behavior) would have
    /// hidden this as a false negative; excluding by ID still catches it.
    func test_duplicate_excludingSelfByID_stillWarnsWhenTwoOthersShareName() {
        let match = HabitNameDuplicateCheck.duplicate(
            of: "Morning Run",
            among: [
                (id: "1", title: "Morning Run"),
                (id: "2", title: "Morning Run"),
                (id: "3", title: "Evening walk")
            ],
            excludingID: "3"
        )
        XCTAssertEqual(match, "Morning Run")
    }
}
