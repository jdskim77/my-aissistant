import XCTest
import SwiftData
@testable import MyAIssistant

@MainActor
final class HabitItemTests: XCTestCase {

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

    // MARK: - Initialization

    func testDefaultInit() {
        let habit = HabitItem(title: "Drink water")
        XCTAssertEqual(habit.title, "Drink water")
        XCTAssertEqual(habit.icon, "\u{2705}")
        XCTAssertEqual(habit.colorHex, "#2D5016")
        XCTAssertEqual(habit.targetDays, .daily)
        XCTAssertNil(habit.archivedAt)
        XCTAssertFalse(habit.isArchived)
        XCTAssertTrue(habit.completionDates.isEmpty)
        XCTAssertNil(habit.reminderHour)
        XCTAssertNil(habit.reminderMinute)
    }

    func testInitWithSpecificDays() {
        let habit = HabitItem(title: "Gym", targetDays: .specificDays([2, 4, 6]))
        XCTAssertEqual(habit.targetDays, .specificDays([2, 4, 6]))
    }

    // MARK: - Completion Tracking

    func testToggleCompletionOn() {
        let habit = HabitItem(title: "Read")
        let today = Date()

        XCTAssertFalse(habit.isCompletedOn(today))
        habit.toggleCompletion(for: today)
        XCTAssertTrue(habit.isCompletedOn(today))
    }

    func testToggleCompletionOff() {
        let habit = HabitItem(title: "Read")
        let today = Date()

        habit.toggleCompletion(for: today)
        XCTAssertTrue(habit.isCompletedOn(today))

        habit.toggleCompletion(for: today)
        XCTAssertFalse(habit.isCompletedOn(today))
    }

    func testCompletionOnDifferentDays() {
        let habit = HabitItem(title: "Meditate")
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        habit.toggleCompletion(for: today)
        habit.toggleCompletion(for: yesterday)

        XCTAssertTrue(habit.isCompletedOn(today))
        XCTAssertTrue(habit.isCompletedOn(yesterday))
        XCTAssertEqual(habit.completionDates.count, 2)
    }

    // MARK: - Streak

    func testCurrentStreakEmpty() {
        let habit = HabitItem(title: "Test")
        XCTAssertEqual(habit.currentStreak(), 0)
    }

    func testCurrentStreakWithTodayCompleted() {
        let habit = HabitItem(title: "Test")
        let today = Calendar.current.startOfDay(for: Date())

        habit.toggleCompletion(for: today)
        XCTAssertEqual(habit.currentStreak(), 1)
    }

    func testCurrentStreakConsecutiveDays() {
        let habit = HabitItem(title: "Test")
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        for offset in 0..<5 {
            let date = cal.date(byAdding: .day, value: -offset, to: today)!
            habit.toggleCompletion(for: date)
        }

        XCTAssertEqual(habit.currentStreak(), 5)
    }

    func testCurrentStreakBrokenByGap() {
        let habit = HabitItem(title: "Test")
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Complete today and yesterday
        habit.toggleCompletion(for: today)
        habit.toggleCompletion(for: cal.date(byAdding: .day, value: -1, to: today)!)
        // Skip day -2, complete day -3
        habit.toggleCompletion(for: cal.date(byAdding: .day, value: -3, to: today)!)

        XCTAssertEqual(habit.currentStreak(), 2)
    }

    func testStreakStartsFromYesterdayIfTodayNotDone() {
        let habit = HabitItem(title: "Test")
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!

        habit.toggleCompletion(for: yesterday)
        habit.toggleCompletion(for: twoDaysAgo)
        // Today not completed

        XCTAssertEqual(habit.currentStreak(), 2)
    }

    // MARK: - Completion Rate

    func testCompletionRateAllDone() {
        let habit = HabitItem(title: "Test")
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        for offset in 0..<7 {
            let date = cal.date(byAdding: .day, value: -offset, to: today)!
            habit.toggleCompletion(for: date)
        }

        let rate = habit.completionRate(days: 7)
        XCTAssertEqual(rate, 1.0, accuracy: 0.01)
    }

    func testCompletionRateNoneDone() {
        let habit = HabitItem(title: "Test")
        let rate = habit.completionRate(days: 7)
        XCTAssertEqual(rate, 0.0, accuracy: 0.01)
    }

    func testCompletionRateWithSpecificDays() {
        let habit = HabitItem(title: "Gym", targetDays: .specificDays([2, 4, 6])) // Mon, Wed, Fri
        // Not completing any days
        let rate = habit.completionRate(days: 30)
        XCTAssertEqual(rate, 0.0, accuracy: 0.01)
    }

    // MARK: - Archived

    func testArchived() {
        let habit = HabitItem(title: "Old habit")
        XCTAssertFalse(habit.isArchived)

        habit.archivedAt = Date()
        XCTAssertTrue(habit.isArchived)
    }

    // MARK: - CompletionDates Computed Property

    func testCompletionDatesComputedProperty() {
        let habit = HabitItem(title: "Test")
        XCTAssertTrue(habit.completionDates.isEmpty)

        habit.completionDatesRaw = "2026-01-01,2026-01-02,2026-01-03"
        XCTAssertEqual(habit.completionDates.count, 3)
        XCTAssertTrue(habit.completionDates.contains("2026-01-01"))
    }

    func testCompletionDatesSetterSorts() {
        let habit = HabitItem(title: "Test")
        habit.completionDates = Set(["2026-01-03", "2026-01-01", "2026-01-02"])
        XCTAssertEqual(habit.completionDatesRaw, "2026-01-01,2026-01-02,2026-01-03")
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() throws {
        let habit = HabitItem(title: "Exercise", icon: "dumbbell", targetDays: .daily)
        habit.toggleCompletion(for: Date())
        context.insert(habit)
        try context.save()

        let descriptor = FetchDescriptor<HabitItem>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "Exercise")
        XCTAssertFalse(fetched.first?.completionDatesRaw.isEmpty ?? true)
    }
}

// MARK: - HabitFrequency Tests

final class HabitFrequencyTests: XCTestCase {

    func testDailyRaw() {
        XCTAssertEqual(HabitFrequency.daily.raw, "daily")
    }

    func testSpecificDaysRaw() {
        let freq = HabitFrequency.specificDays([2, 4, 6])
        XCTAssertEqual(freq.raw, "2,4,6")
    }

    func testInitFromDailyRaw() {
        let freq = HabitFrequency(raw: "daily")
        XCTAssertEqual(freq, .daily)
    }

    func testInitFromSpecificDaysRaw() {
        let freq = HabitFrequency(raw: "2,4,6")
        XCTAssertEqual(freq, .specificDays([2, 4, 6]))
    }

    func testInitFromEmptyStringDefaultsToDaily() {
        let freq = HabitFrequency(raw: "")
        XCTAssertEqual(freq, .daily)
    }

    func testInitFromInvalidStringDefaultsToDaily() {
        let freq = HabitFrequency(raw: "abc,def")
        XCTAssertEqual(freq, .daily)
    }

    func testDailyAppliesToAllDays() {
        let freq = HabitFrequency.daily
        let cal = Calendar.current
        let today = Date()
        for offset in 0..<7 {
            let date = cal.date(byAdding: .day, value: offset, to: today)!
            XCTAssertTrue(freq.appliesTo(date: date))
        }
    }

    func testSpecificDaysAppliesCorrectly() {
        // Only Monday (weekday 2)
        let freq = HabitFrequency.specificDays([2])
        // Find next Monday
        let cal = Calendar.current
        var date = Date()
        while cal.component(.weekday, from: date) != 2 {
            date = cal.date(byAdding: .day, value: 1, to: date)!
        }
        XCTAssertTrue(freq.appliesTo(date: date))

        // Next day (Tuesday) should not apply
        let tuesday = cal.date(byAdding: .day, value: 1, to: date)!
        XCTAssertFalse(freq.appliesTo(date: tuesday))
    }

    func testDisplayLabelDaily() {
        XCTAssertEqual(HabitFrequency.daily.displayLabel, "Every day")
    }

    func testDisplayLabelSpecificDays() {
        let freq = HabitFrequency.specificDays([2, 4, 6])
        XCTAssertEqual(freq.displayLabel, "Mon, Wed, Fri")
    }
}
