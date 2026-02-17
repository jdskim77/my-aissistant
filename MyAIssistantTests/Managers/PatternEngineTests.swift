import XCTest
import SwiftData
@testable import MyAIssistant

@MainActor
final class PatternEngineTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var sut: PatternEngine!

    override func setUp() async throws {
        container = try TestModelContainer.create()
        context = container.mainContext
        sut = PatternEngine(modelContext: context)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        sut = nil
    }

    // MARK: - Helpers

    private func addTask(daysAgo: Int = 0, done: Bool = false, category: TaskCategory = .personal) {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let task = TaskItem(
            title: "Task \(daysAgo)",
            category: category,
            priority: .medium,
            date: date,
            done: done,
            icon: "📝"
        )
        context.insert(task)
        try? context.save()
    }

    private func addCheckIn(daysAgo: Int = 0, timeSlot: CheckInTime = .morning, completed: Bool = true, mood: Int? = nil) {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let record = CheckInRecord(
            timeSlot: timeSlot,
            date: date,
            completed: completed,
            mood: mood
        )
        context.insert(record)
        try? context.save()
    }

    // MARK: - Streak Tests

    func testCurrentStreakNoTasks() {
        let streak = sut.currentStreak()
        XCTAssertEqual(streak, 0)
    }

    func testCurrentStreakWithConsecutiveDays() {
        // Complete tasks today, yesterday, and 2 days ago
        addTask(daysAgo: 0, done: true)
        addTask(daysAgo: 1, done: true)
        addTask(daysAgo: 2, done: true)

        let streak = sut.currentStreak()
        XCTAssertEqual(streak, 3)
    }

    func testCurrentStreakBrokenByGap() {
        // Complete today and 2 days ago (gap yesterday)
        addTask(daysAgo: 0, done: true)
        addTask(daysAgo: 2, done: true)

        let streak = sut.currentStreak()
        XCTAssertEqual(streak, 1) // Only today counts
    }

    func testCurrentStreakOnlyIncompleteTasks() {
        addTask(daysAgo: 0, done: false)
        addTask(daysAgo: 1, done: false)

        let streak = sut.currentStreak()
        XCTAssertEqual(streak, 0)
    }

    // MARK: - Completion Rate Tests

    func testCompletionRateEmpty() {
        let rate = sut.completionRate()
        XCTAssertEqual(rate, 0)
    }

    func testCompletionRateAllDone() {
        addTask(daysAgo: 0, done: true)
        addTask(daysAgo: 1, done: true)

        let rate = sut.completionRate()
        XCTAssertEqual(rate, 100)
    }

    func testCompletionRatePartial() {
        addTask(daysAgo: 0, done: true)
        addTask(daysAgo: 0, done: false)

        let rate = sut.completionRate()
        XCTAssertEqual(rate, 50)
    }

    // MARK: - Average Tasks Per Day

    func testAverageTasksPerDayEmpty() {
        let avg = sut.averageTasksPerDay(days: 7)
        XCTAssertEqual(avg, 0)
    }

    func testAverageTasksPerDay() {
        // 3 tasks in last 7 days
        addTask(daysAgo: 0)
        addTask(daysAgo: 1)
        addTask(daysAgo: 2)

        let avg = sut.averageTasksPerDay(days: 7)
        XCTAssertEqual(avg, 3.0 / 7.0, accuracy: 0.01)
    }

    // MARK: - Category Breakdown

    func testCategoryBreakdown() {
        addTask(daysAgo: 0, done: true, category: .work)
        addTask(daysAgo: 0, done: false, category: .work)
        addTask(daysAgo: 0, done: true, category: .personal)

        let breakdown = sut.categoryBreakdown()

        let work = breakdown.first(where: { $0.category == .work })
        XCTAssertEqual(work?.done, 1)
        XCTAssertEqual(work?.total, 2)

        let personal = breakdown.first(where: { $0.category == .personal })
        XCTAssertEqual(personal?.done, 1)
        XCTAssertEqual(personal?.total, 1)
    }

    // MARK: - Check-in Consistency

    func testCheckInConsistencyEmpty() {
        let consistency = sut.checkInConsistency()
        XCTAssertEqual(consistency.count, 7)
        XCTAssertTrue(consistency.allSatisfy { !$0 })
    }

    func testCheckInConsistencyWithRecords() {
        // Add a completed check-in for today
        addCheckIn(daysAgo: 0, completed: true)

        let consistency = sut.checkInConsistency()
        XCTAssertEqual(consistency.count, 7)
        XCTAssertTrue(consistency.last!) // Today should be true
    }

    // MARK: - Best Check-in Time

    func testBestCheckInTimeEmpty() {
        let best = sut.bestCheckInTime()
        // Default to morning when no data
        XCTAssertEqual(best, CheckInTime.morning.rawValue)
    }

    func testBestCheckInTimeWithData() {
        // More afternoon check-ins than others
        addCheckIn(daysAgo: 0, timeSlot: .afternoon, completed: true)
        addCheckIn(daysAgo: 1, timeSlot: .afternoon, completed: true)
        addCheckIn(daysAgo: 2, timeSlot: .afternoon, completed: true)
        addCheckIn(daysAgo: 0, timeSlot: .morning, completed: true)

        let best = sut.bestCheckInTime()
        XCTAssertEqual(best, CheckInTime.afternoon.rawValue)
    }

    // MARK: - Mood Trend

    func testMoodTrendEmpty() {
        let trend = sut.moodTrend(days: 7)
        XCTAssertTrue(trend.isEmpty)
    }

    func testMoodTrendWithData() {
        // Add check-in with mood + task for today
        addCheckIn(daysAgo: 0, completed: true, mood: 4)
        addTask(daysAgo: 0, done: true)

        let trend = sut.moodTrend(days: 7)
        XCTAssertEqual(trend.count, 1)
        XCTAssertEqual(trend.first!.mood, 4.0, accuracy: 0.01)
        XCTAssertEqual(trend.first!.completionRate, 1.0, accuracy: 0.01)
    }

    // MARK: - Mood-Productivity Correlation

    func testMoodProductivityCorrelationInsufficientData() {
        // Need at least 5 data points
        addCheckIn(daysAgo: 0, completed: true, mood: 4)
        addTask(daysAgo: 0, done: true)

        let correlation = sut.moodProductivityCorrelation()
        XCTAssertNil(correlation) // Not enough data
    }
}
