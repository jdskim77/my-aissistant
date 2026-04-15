import XCTest
@testable import MyAIssistant

/// Smoke tests for the iPhone↔Watch sync payload.
///
/// These are the cheapest insurance against silently breaking the
/// WatchConnectivity contract: if a property gets renamed/reordered in
/// the iOS copy without matching the Watch copy, decoding on the Watch
/// silently produces nil and the entire Watch experience breaks.
///
/// What this protects:
///   - The applicationContext dictionary wrapper (`watchScheduleDict`)
///   - Codable round-trip (encode → JSON → decode preserves values)
///   - Optional fields default-handle correctly
///   - WatchTask sub-struct round-trips
///
/// Pre-fork value: ANY change to WatchScheduleData (during the surf-app
/// strip-and-replace work) must keep these tests passing or the Watch
/// transport silently breaks.
final class WatchScheduleDataTests: XCTestCase {

    // MARK: - Round-trip via Dictionary (the actual transport path)

    func testDictionaryRoundTripPreservesAllPopulatedFields() throws {
        let original = makeFullPayload()

        let dict = original.toDictionary()
        XCTAssertNotNil(dict["watchScheduleDict"], "Transport key missing — Watch will not decode")

        guard let decoded = WatchScheduleData.from(context: dict) else {
            XCTFail("Failed to decode round-tripped payload")
            return
        }

        XCTAssertEqual(decoded.streakDays, original.streakDays)
        XCTAssertEqual(decoded.completedToday, original.completedToday)
        XCTAssertEqual(decoded.totalToday, original.totalToday)
        XCTAssertEqual(decoded.quoteText, original.quoteText)
        XCTAssertEqual(decoded.quoteAuthor, original.quoteAuthor)
        XCTAssertEqual(decoded.nextCheckIn, original.nextCheckIn)
        XCTAssertEqual(decoded.bodyScore, original.bodyScore)
        XCTAssertEqual(decoded.mindScore, original.mindScore)
        XCTAssertEqual(decoded.heartScore, original.heartScore)
        XCTAssertEqual(decoded.spiritScore, original.spiritScore)
        XCTAssertEqual(decoded.userName, original.userName)
        XCTAssertEqual(decoded.aiInsight, original.aiInsight)
        XCTAssertEqual(decoded.completedCheckIns, original.completedCheckIns)
        XCTAssertEqual(decoded.tasks.count, original.tasks.count)
    }

    func testRoundTripWithAllOptionalsNil() throws {
        let minimal = WatchScheduleData(
            tasks: [],
            streakDays: 0,
            completedToday: 0,
            totalToday: 0,
            quoteText: nil,
            quoteAuthor: nil,
            nextCheckIn: nil,
            updatedAt: Date(),
            bodyScore: nil,
            mindScore: nil,
            heartScore: nil,
            spiritScore: nil,
            userName: nil,
            aiInsight: nil,
            completedCheckIns: nil
        )

        let dict = minimal.toDictionary()
        let decoded = WatchScheduleData.from(context: dict)

        XCTAssertNotNil(decoded)
        XCTAssertNil(decoded?.quoteText)
        XCTAssertNil(decoded?.quoteAuthor)
        XCTAssertNil(decoded?.nextCheckIn)
        XCTAssertNil(decoded?.bodyScore)
        XCTAssertNil(decoded?.mindScore)
        XCTAssertNil(decoded?.heartScore)
        XCTAssertNil(decoded?.spiritScore)
        XCTAssertNil(decoded?.userName)
        XCTAssertNil(decoded?.aiInsight)
        XCTAssertNil(decoded?.completedCheckIns)
        XCTAssertEqual(decoded?.tasks.count, 0)
    }

    func testWatchTaskRoundTripPreservesFields() throws {
        let task = WatchScheduleData.WatchTask(
            id: "task-123",
            title: "Buy groceries",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            priorityRaw: "High",
            categoryRaw: "Personal",
            done: false,
            isCalendarEvent: false,
            recurrenceRaw: "daily"
        )
        let payload = WatchScheduleData(
            tasks: [task],
            streakDays: 0,
            completedToday: 0,
            totalToday: 1,
            quoteText: nil,
            quoteAuthor: nil,
            nextCheckIn: nil,
            updatedAt: Date(),
            bodyScore: nil,
            mindScore: nil,
            heartScore: nil,
            spiritScore: nil,
            userName: nil,
            aiInsight: nil,
            completedCheckIns: nil
        )

        let decoded = WatchScheduleData.from(context: payload.toDictionary())
        let decodedTask = try XCTUnwrap(decoded?.tasks.first)

        XCTAssertEqual(decodedTask.id, task.id)
        XCTAssertEqual(decodedTask.title, task.title)
        XCTAssertEqual(decodedTask.date.timeIntervalSince1970, task.date.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(decodedTask.priorityRaw, task.priorityRaw)
        XCTAssertEqual(decodedTask.categoryRaw, task.categoryRaw)
        XCTAssertEqual(decodedTask.done, task.done)
        XCTAssertEqual(decodedTask.isCalendarEvent, task.isCalendarEvent)
        XCTAssertEqual(decodedTask.recurrenceRaw, task.recurrenceRaw)
    }

    // MARK: - Decoding edge cases

    func testFromContextReturnsNilForEmptyDictionary() {
        XCTAssertNil(WatchScheduleData.from(context: [:]))
    }

    func testFromContextReturnsNilForGarbagePayload() {
        let garbage: [String: Any] = ["watchScheduleDict": "not a dictionary"]
        XCTAssertNil(WatchScheduleData.from(context: garbage))
    }

    func testFromContextLegacyDataPathStillDecodes() throws {
        // Older Thrivn versions sent raw Data under "watchSchedule". The decoder
        // should still handle that path so users mid-update don't lose sync.
        let payload = makeFullPayload()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(payload)
        let legacyContext: [String: Any] = ["watchSchedule": data]

        let decoded = WatchScheduleData.from(context: legacyContext)
        XCTAssertNotNil(decoded, "Legacy raw-Data path broken — mid-update users will lose Watch sync")
        XCTAssertEqual(decoded?.streakDays, payload.streakDays)
    }

    // MARK: - Fixture

    private func makeFullPayload() -> WatchScheduleData {
        let task = WatchScheduleData.WatchTask(
            id: UUID().uuidString,
            title: "Sample task",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            priorityRaw: "Medium",
            categoryRaw: "Work",
            done: false,
            isCalendarEvent: false,
            recurrenceRaw: nil
        )
        return WatchScheduleData(
            tasks: [task],
            streakDays: 7,
            completedToday: 3,
            totalToday: 5,
            quoteText: "Be water, my friend",
            quoteAuthor: "Bruce Lee",
            nextCheckIn: "Midday",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            bodyScore: 7.0,
            mindScore: 6.5,
            heartScore: 8.0,
            spiritScore: 5.5,
            userName: "Joe",
            aiInsight: "You're trending up across all dimensions this week.",
            completedCheckIns: ["Morning", "Midday"]
        )
    }
}
