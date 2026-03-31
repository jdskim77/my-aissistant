import XCTest
import SwiftData
@testable import MyAIssistant

@MainActor
final class BackgroundTaskManagerTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try TestModelContainer.create()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // MARK: - Task Identifiers

    func testDailySnapshotID() {
        XCTAssertEqual(BackgroundTaskManager.dailySnapshotID, "com.myaissistant.daily-snapshot")
    }

    func testWeeklyReviewID() {
        XCTAssertEqual(BackgroundTaskManager.weeklyReviewID, "com.myaissistant.weekly-review")
    }

    func testCalendarSyncID() {
        XCTAssertEqual(BackgroundTaskManager.calendarSyncID, "com.myaissistant.calendar-sync")
    }

    // MARK: - Initialization

    func testInitialization() {
        let patternEngine = PatternEngine(modelContext: context)
        let calSyncManager = CalendarSyncManager(modelContext: context)
        let sut = BackgroundTaskManager(
            modelContext: context,
            patternEngine: patternEngine,
            calendarSyncManager: calSyncManager
        )
        // Verify it can be created without crashing
        XCTAssertNotNil(sut)
    }

    // MARK: - Daily Snapshot Data Verification

    func testDailySnapshotDataGathering() throws {
        // Set up tasks and check-ins for yesterday to verify snapshot data collection
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
        let yesterdayEnd = cal.date(byAdding: .day, value: 1, to: yesterday)!

        // Add 3 tasks for yesterday, 2 completed
        let task1 = TaskItem(title: "T1", category: .work, priority: .high, date: yesterday, done: true, icon: "a")
        let task2 = TaskItem(title: "T2", category: .work, priority: .medium, date: yesterday, done: true, icon: "b")
        let task3 = TaskItem(title: "T3", category: .personal, priority: .low, date: yesterday, icon: "c")
        context.insert(task1)
        context.insert(task2)
        context.insert(task3)

        // Add check-in for yesterday with mood
        let checkIn = CheckInRecord(timeSlot: .morning, date: yesterday, completed: true, mood: 4)
        context.insert(checkIn)
        try context.save()

        // Verify the tasks are queryable for yesterday's date range
        let taskDescriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= yesterday && $0.date < yesterdayEnd }
        )
        let tasks = try context.fetch(taskDescriptor)
        XCTAssertEqual(tasks.count, 3)

        let doneDescriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= yesterday && $0.date < yesterdayEnd && $0.done == true }
        )
        let doneTasks = try context.fetch(doneDescriptor)
        XCTAssertEqual(doneTasks.count, 2)

        let checkInDescriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { $0.date >= yesterday && $0.date < yesterdayEnd && $0.completed == true }
        )
        let checkIns = try context.fetch(checkInDescriptor)
        XCTAssertEqual(checkIns.count, 1)
        XCTAssertEqual(checkIns.first?.mood, 4)
    }

    // MARK: - DailySnapshot Model

    func testDailySnapshotCreation() throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!

        let snapshot = DailySnapshot(
            date: yesterday,
            tasksTotal: 5,
            tasksCompleted: 3,
            checkInsCompleted: 2,
            averageMood: 3.5,
            streakCount: 4
        )
        context.insert(snapshot)
        try context.save()

        let descriptor = FetchDescriptor<DailySnapshot>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.tasksTotal, 5)
        XCTAssertEqual(fetched.first?.tasksCompleted, 3)
        XCTAssertEqual(fetched.first?.checkInsCompleted, 2)
        XCTAssertEqual(fetched.first?.averageMood, 3.5, accuracy: 0.01)
        XCTAssertEqual(fetched.first?.streakCount, 4)
    }

    // MARK: - Weekly Review Constants

    func testWeeklyReviewConstants() {
        // Sunday = 1 in Calendar
        XCTAssertEqual(AppConstants.weeklyReviewDay, 1)
        XCTAssertEqual(AppConstants.weeklyReviewHour, 21)
    }
}
