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
            among: ["Morning Run", "Evening walk"]
        )
        XCTAssertEqual(match, "Morning Run")
    }

    func test_duplicate_punctuationInsensitiveMatch_detected() {
        let match = HabitNameDuplicateCheck.duplicate(
            of: "10 Surf popups!",
            among: ["10 surf popups"]
        )
        XCTAssertEqual(match, "10 surf popups")
    }

    func test_duplicate_noMatch_returnsNil() {
        let match = HabitNameDuplicateCheck.duplicate(
            of: "Meditate",
            among: ["Morning Run", "Evening walk"]
        )
        XCTAssertNil(match)
    }

    func test_duplicate_emptyCandidate_returnsNil() {
        let match = HabitNameDuplicateCheck.duplicate(
            of: "   ",
            among: ["Morning Run"]
        )
        XCTAssertNil(match)
    }

    func test_duplicate_excludingSelf_doesNotWarnOnUnchangedEdit() {
        let match = HabitNameDuplicateCheck.duplicate(
            of: "Morning Run",
            among: ["Morning Run", "Evening walk"],
            excluding: "Morning Run"
        )
        XCTAssertNil(match)
    }

    func test_duplicate_excludingSelf_stillWarnsOnOtherCollision() {
        let match = HabitNameDuplicateCheck.duplicate(
            of: "Evening Walk",
            among: ["Morning Run", "Evening walk"],
            excluding: "Morning Run"
        )
        XCTAssertEqual(match, "Evening walk")
    }
}
