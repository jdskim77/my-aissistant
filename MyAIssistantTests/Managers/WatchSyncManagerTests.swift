import XCTest
@testable import MyAIssistant

/// Covers `WatchSyncManager.buildSchedulePayload`, the pure day-window +
/// payload-shaping logic factored out of `syncSchedule` (zero test coverage
/// backlog item). `now` is injected so day-boundary and check-in-slot
/// behavior are deterministic instead of depending on the real clock.
@MainActor
final class WatchSyncManagerTests: XCTestCase {

    private let calendar = Calendar.current

    private func makeTask(
        title: String = "Test Task",
        category: TaskCategory = .personal,
        priority: TaskPriority = .medium,
        date: Date,
        done: Bool = false,
        icon: String = "📝"
    ) -> TaskItem {
        TaskItem(
            title: title,
            category: category,
            priority: priority,
            date: date,
            done: done,
            icon: icon
        )
    }

    private func date(year: Int = 2026, month: Int = 3, day: Int = 15, hour: Int) -> Date {
        DateComponents(calendar: calendar, year: year, month: month, day: day, hour: hour).date!
    }

    func testFiltersToToday() {
        let now = date(hour: 10)
        let todayStart = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        let tasks = [
            makeTask(title: "Yesterday", date: yesterday.addingTimeInterval(3600)),
            makeTask(title: "Today AM", date: todayStart.addingTimeInterval(3600)),
            makeTask(title: "Today PM", date: todayStart.addingTimeInterval(20 * 3600)),
            makeTask(title: "Tomorrow", date: tomorrow.addingTimeInterval(3600)),
        ]

        let payload = WatchSyncManager.buildSchedulePayload(
            tasks: tasks,
            streak: 3,
            quoteText: nil,
            quoteAuthor: nil,
            compassScores: nil,
            userName: nil,
            aiInsight: nil,
            completedCheckIns: nil,
            now: now
        )

        XCTAssertEqual(payload.tasks.count, 2)
        XCTAssertEqual(payload.tasks.map(\.title), ["Today AM", "Today PM"])
        XCTAssertEqual(payload.totalToday, 2)
    }

    func testSortsByDate() {
        let now = date(hour: 10)
        let todayStart = calendar.startOfDay(for: now)

        let tasks = [
            makeTask(title: "Later", date: todayStart.addingTimeInterval(18 * 3600)),
            makeTask(title: "Earlier", date: todayStart.addingTimeInterval(7 * 3600)),
            makeTask(title: "Middle", date: todayStart.addingTimeInterval(12 * 3600)),
        ]

        let payload = WatchSyncManager.buildSchedulePayload(
            tasks: tasks, streak: 0, quoteText: nil, quoteAuthor: nil,
            compassScores: nil, userName: nil, aiInsight: nil,
            completedCheckIns: nil, now: now
        )

        XCTAssertEqual(payload.tasks.map(\.title), ["Earlier", "Middle", "Later"])
    }

    func testCountsCompleted() {
        let now = date(hour: 10)
        let todayStart = calendar.startOfDay(for: now)

        let tasks = [
            makeTask(title: "Done 1", date: todayStart.addingTimeInterval(3600), done: true),
            makeTask(title: "Done 2", date: todayStart.addingTimeInterval(7200), done: true),
            makeTask(title: "Not done", date: todayStart.addingTimeInterval(10800), done: false),
        ]

        let payload = WatchSyncManager.buildSchedulePayload(
            tasks: tasks, streak: 5, quoteText: nil, quoteAuthor: nil,
            compassScores: nil, userName: nil, aiInsight: nil,
            completedCheckIns: nil, now: now
        )

        XCTAssertEqual(payload.completedToday, 2)
        XCTAssertEqual(payload.totalToday, 3)
        XCTAssertEqual(payload.streakDays, 5)
    }

    func testNextCheckInMatchesHourSlot() {
        let cases: [(Int, String)] = [(6, "Morning"), (14, "Midday"), (19, "Afternoon"), (22, "Night")]
        for (hour, expectedSlot) in cases {
            let now = date(hour: hour)
            let payload = WatchSyncManager.buildSchedulePayload(
                tasks: [], streak: 0, quoteText: nil, quoteAuthor: nil,
                compassScores: nil, userName: nil, aiInsight: nil,
                completedCheckIns: nil, now: now
            )
            XCTAssertEqual(payload.nextCheckIn, expectedSlot, "hour \(hour) should map to \(expectedSlot)")
        }
    }

    func testPassesThroughMetadataUnchanged() {
        let now = date(hour: 9)

        let payload = WatchSyncManager.buildSchedulePayload(
            tasks: [],
            streak: 7,
            quoteText: "Stay the course.",
            quoteAuthor: "Someone",
            compassScores: (body: 0.5, mind: 0.6, heart: 0.7, spirit: 0.8),
            userName: "Joe",
            aiInsight: "Keep it up",
            completedCheckIns: ["Morning", "Midday"],
            now: now
        )

        XCTAssertEqual(payload.quoteText, "Stay the course.")
        XCTAssertEqual(payload.quoteAuthor, "Someone")
        XCTAssertEqual(payload.bodyScore, 0.5)
        XCTAssertEqual(payload.mindScore, 0.6)
        XCTAssertEqual(payload.heartScore, 0.7)
        XCTAssertEqual(payload.spiritScore, 0.8)
        XCTAssertEqual(payload.userName, "Joe")
        XCTAssertEqual(payload.aiInsight, "Keep it up")
        XCTAssertEqual(payload.completedCheckIns, ["Morning", "Midday"])
        XCTAssertEqual(payload.updatedAt, now)
    }

    func testEmptyTaskListProducesZeroCountsNotACrash() {
        let now = date(hour: 9)

        let payload = WatchSyncManager.buildSchedulePayload(
            tasks: [], streak: 0, quoteText: nil, quoteAuthor: nil,
            compassScores: nil, userName: nil, aiInsight: nil,
            completedCheckIns: nil, now: now
        )

        XCTAssertTrue(payload.tasks.isEmpty)
        XCTAssertEqual(payload.totalToday, 0)
        XCTAssertEqual(payload.completedToday, 0)
    }

    func testMapsWatchTaskFields() {
        let now = date(hour: 9)
        let todayStart = calendar.startOfDay(for: now)

        let task = makeTask(
            title: "Run",
            category: .health,
            priority: .high,
            date: todayStart.addingTimeInterval(3600)
        )
        task.recurrenceRaw = TaskRecurrence.daily.rawValue
        task.dimensions = [.physical]
        task.externalCalendarID = "cal-123"

        let payload = WatchSyncManager.buildSchedulePayload(
            tasks: [task], streak: 0, quoteText: nil, quoteAuthor: nil,
            compassScores: nil, userName: nil, aiInsight: nil,
            completedCheckIns: nil, now: now
        )

        let watchTask = try! XCTUnwrap(payload.tasks.first)
        XCTAssertEqual(watchTask.id, task.id)
        XCTAssertEqual(watchTask.title, "Run")
        XCTAssertEqual(watchTask.priorityRaw, TaskPriority.high.rawValue)
        XCTAssertEqual(watchTask.categoryRaw, TaskCategory.health.rawValue)
        XCTAssertTrue(watchTask.isCalendarEvent)
        XCTAssertEqual(watchTask.recurrenceRaw, TaskRecurrence.daily.rawValue)
        XCTAssertEqual(watchTask.dimensionsRaw, LifeDimension.physical.rawValue)
    }
}
