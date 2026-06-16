import XCTest
import SwiftData
@testable import MyAIssistant

/// Tests for `ChatManager.parseResponseTags(from:)` — the parser that
/// converts AI-emitted action tags (`[[CREATE_EVENT:...]]`,
/// `[[DELETE_EVENT:...]]`) into structured `CalendarAction` values.
///
/// The most important test in this file is the dimension fallback:
/// the AI prompt declares `dimension` REQUIRED on every CREATE_EVENT,
/// but "REQUIRED" is a soft constraint on the model. The parser
/// defaults missing dimensions to `.practical` so an omission can never
/// reproduce the original user-reported animation regression
/// (untagged tasks landing without a dimension and never firing the
/// BalancePulse). These tests pin that defense-in-depth behavior.
@MainActor
final class ChatManagerParserTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var sut: ChatManager!

    override func setUp() async throws {
        container = try TestModelContainer.create()
        context = container.mainContext
        sut = ChatManager(modelContext: context)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        sut = nil
    }

    // MARK: - Dimension fallback (regression gate for animation report)

    func test_parse_createEventWithDimension_preservesDimension() {
        let text = "[[CREATE_EVENT:Morning walk|2026-05-01 07:00|2026-05-01 07:30||none|physical]]"
        let result = sut.parseResponseTags(from: text)

        XCTAssertEqual(result.calendarActions.count, 1)
        if case .create(_, _, _, _, _, let dim) = result.calendarActions[0] {
            XCTAssertEqual(dim, .physical)
        } else {
            XCTFail("Expected a .create action")
        }
    }

    func test_parse_createEventMissingDimension_defaultsToPractical() {
        // Prompt declares dimension REQUIRED but the model occasionally
        // omits it — the parser fallback ensures the task still lands
        // tagged (defense-in-depth from the AI-prompt + parser fix).
        // Without this, the "Cancel hotel" regression returns: untagged
        // task → no BalancePulse on completion.
        let text = "[[CREATE_EVENT:Cancel hotel|2026-05-01 18:00|2026-05-01 19:00]]"
        let result = sut.parseResponseTags(from: text)

        XCTAssertEqual(result.calendarActions.count, 1)
        if case .create(_, _, _, _, _, let dim) = result.calendarActions[0] {
            XCTAssertEqual(dim, .practical,
                           "Missing dimension must default to .practical, never nil.")
        } else {
            XCTFail("Expected a .create action")
        }
    }

    func test_parse_createEventWithEmptyDimensionSlot_defaultsToPractical() {
        // Trailing empty slot (model emitted the pipe but no token).
        let text = "[[CREATE_EVENT:Renew passport|2026-05-01 10:00|2026-05-01 10:30||none|]]"
        let result = sut.parseResponseTags(from: text)

        XCTAssertEqual(result.calendarActions.count, 1)
        if case .create(_, _, _, _, _, let dim) = result.calendarActions[0] {
            XCTAssertEqual(dim, .practical)
        } else {
            XCTFail("Expected a .create action")
        }
    }

    func test_parse_createEventPracticalExplicit_preservesPractical() {
        let text = "[[CREATE_EVENT:Pay bills|2026-05-01 14:00|2026-05-01 14:30||none|practical]]"
        let result = sut.parseResponseTags(from: text)

        XCTAssertEqual(result.calendarActions.count, 1)
        if case .create(_, _, _, _, _, let dim) = result.calendarActions[0] {
            XCTAssertEqual(dim, .practical)
        } else {
            XCTFail("Expected a .create action")
        }
    }

    // MARK: - Field classification (order-tolerant parsing)

    func test_parse_recurrenceAndDimension_inEitherOrder() {
        // The parser classifies trailing fields by content, not position,
        // so "daily|physical" and "physical|daily" both work.
        let dailyFirst = sut.parseResponseTags(
            from: "[[CREATE_EVENT:Stretch|2026-05-01 21:00|2026-05-01 21:15||daily|physical]]"
        )
        let physicalFirst = sut.parseResponseTags(
            from: "[[CREATE_EVENT:Stretch|2026-05-01 21:00|2026-05-01 21:15||physical|daily]]"
        )

        XCTAssertEqual(dailyFirst.calendarActions.count, 1)
        XCTAssertEqual(physicalFirst.calendarActions.count, 1)

        if case .create(_, _, _, _, let recA, let dimA) = dailyFirst.calendarActions[0],
           case .create(_, _, _, _, let recB, let dimB) = physicalFirst.calendarActions[0] {
            XCTAssertEqual(recA, .daily)
            XCTAssertEqual(dimA, .physical)
            XCTAssertEqual(recB, .daily)
            XCTAssertEqual(dimB, .physical)
        } else {
            XCTFail("Expected create actions in both")
        }
    }

    func test_parse_caseInsensitiveDimensionToken() {
        // Defensive — model may emit "Physical" (capitalized) under some
        // sampling. Parser lowercases before keyword matching.
        let text = "[[CREATE_EVENT:Walk|2026-05-01 07:00|2026-05-01 07:30||none|Physical]]"
        let result = sut.parseResponseTags(from: text)

        XCTAssertEqual(result.calendarActions.count, 1)
        if case .create(_, _, _, _, _, let dim) = result.calendarActions[0] {
            XCTAssertEqual(dim, .physical)
        } else {
            XCTFail("Expected a .create action")
        }
    }

    // MARK: - Tag stripping

    func test_parse_displayTextStripsCreateTag() {
        let text = "Sounds good. [[CREATE_EVENT:Walk|2026-05-01 07:00|2026-05-01 07:30||none|physical]] Have fun."
        let result = sut.parseResponseTags(from: text)

        XCTAssertFalse(result.displayText.contains("[[CREATE_EVENT"),
                       "CREATE_EVENT tag must be stripped from displayText.")
        XCTAssertTrue(result.displayText.contains("Sounds good."))
        XCTAssertTrue(result.displayText.contains("Have fun."))
    }

    // MARK: - Malformed tags

    func test_parse_malformedTag_dropsItSilently() {
        // Fewer than 3 pipe-separated parts → tag is invalid; parser
        // strips it from displayText but emits no calendarAction.
        let text = "[[CREATE_EVENT:onlyTitle|2026-05-01 07:00]]"
        let result = sut.parseResponseTags(from: text)

        XCTAssertEqual(result.calendarActions.count, 0)
        XCTAssertFalse(result.displayText.contains("[[CREATE_EVENT"))
    }

    func test_parse_invalidDate_dropsAction() {
        // Date doesn't parse → action skipped.
        let text = "[[CREATE_EVENT:Walk|not-a-date|also-not|none|physical]]"
        let result = sut.parseResponseTags(from: text)

        XCTAssertEqual(result.calendarActions.count, 0)
    }

    func test_parse_noTags_returnsTextUnchanged() {
        let text = "Just a regular message with no tags."
        let result = sut.parseResponseTags(from: text)

        XCTAssertEqual(result.displayText.trimmingCharacters(in: .whitespacesAndNewlines), text)
        XCTAssertEqual(result.calendarActions.count, 0)
    }

    // MARK: - Multiple tags

    func test_parse_multipleCreateTags_allProcessed() {
        let text = """
        [[CREATE_EVENT:Walk|2026-05-01 07:00|2026-05-01 07:30||none|physical]]
        [[CREATE_EVENT:Read|2026-05-01 21:00|2026-05-01 22:00||none|mental]]
        [[CREATE_EVENT:Errand|2026-05-01 14:00|2026-05-01 14:30]]
        """
        let result = sut.parseResponseTags(from: text)

        XCTAssertEqual(result.calendarActions.count, 3)
        let dimensions: [LifeDimension?] = result.calendarActions.compactMap { action in
            if case .create(_, _, _, _, _, let dim) = action { return dim }
            return nil
        }
        XCTAssertEqual(dimensions, [.physical, .mental, .practical],
                       "Third tag had no dimension; must default to .practical via fallback.")
    }
}
