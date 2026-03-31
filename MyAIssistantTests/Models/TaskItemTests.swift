import XCTest
import SwiftData
@testable import MyAIssistant

@MainActor
final class TaskItemTests: XCTestCase {

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

    func testDefaultInitialization() {
        let task = TaskItem(
            title: "Buy groceries",
            category: .errand,
            priority: .high,
            date: Date(),
            icon: "cart"
        )

        XCTAssertEqual(task.title, "Buy groceries")
        XCTAssertEqual(task.category, .errand)
        XCTAssertEqual(task.priority, .high)
        XCTAssertFalse(task.done)
        XCTAssertNil(task.completedAt)
        XCTAssertNil(task.externalCalendarID)
        XCTAssertEqual(task.notes, "")
        XCTAssertEqual(task.recurrence, .none)
        XCTAssertFalse(task.id.isEmpty)
    }

    func testInitializationWithDoneTrue() {
        let task = TaskItem(
            title: "Done Task",
            category: .work,
            priority: .low,
            date: Date(),
            done: true,
            icon: "check"
        )

        XCTAssertTrue(task.done)
        XCTAssertNotNil(task.completedAt)
    }

    func testInitializationWithRecurrence() {
        let task = TaskItem(
            title: "Weekly meeting",
            category: .work,
            priority: .medium,
            date: Date(),
            icon: "calendar",
            recurrence: .weekly
        )

        XCTAssertEqual(task.recurrence, .weekly)
        XCTAssertEqual(task.recurrenceRaw, "Weekly")
    }

    func testInitializationWithNoneRecurrence() {
        let task = TaskItem(
            title: "One-off",
            category: .personal,
            priority: .low,
            date: Date(),
            icon: "star"
        )

        XCTAssertEqual(task.recurrence, .none)
        XCTAssertNil(task.recurrenceRaw)
    }

    // MARK: - Computed Category

    func testCategoryComputedProperty() {
        let task = TaskItem(title: "Test", category: .work, priority: .medium, date: Date(), icon: "t")
        XCTAssertEqual(task.category, .work)

        task.category = .health
        XCTAssertEqual(task.categoryRaw, "Health")
        XCTAssertEqual(task.category, .health)
    }

    func testCategoryFallbackToPersonal() {
        let task = TaskItem(title: "Test", category: .work, priority: .medium, date: Date(), icon: "t")
        task.categoryRaw = "InvalidCategory"
        XCTAssertEqual(task.category, .personal)
    }

    // MARK: - Computed Priority

    func testPriorityComputedProperty() {
        let task = TaskItem(title: "Test", category: .work, priority: .high, date: Date(), icon: "t")
        XCTAssertEqual(task.priority, .high)

        task.priority = .low
        XCTAssertEqual(task.priorityRaw, "Low")
        XCTAssertEqual(task.priority, .low)
    }

    func testPriorityFallbackToMedium() {
        let task = TaskItem(title: "Test", category: .work, priority: .high, date: Date(), icon: "t")
        task.priorityRaw = "InvalidPriority"
        XCTAssertEqual(task.priority, .medium)
    }

    // MARK: - Computed Recurrence

    func testRecurrenceSetterClearsRawForNone() {
        let task = TaskItem(title: "Test", category: .work, priority: .medium, date: Date(), icon: "t", recurrence: .daily)
        XCTAssertEqual(task.recurrenceRaw, "Daily")

        task.recurrence = .none
        XCTAssertNil(task.recurrenceRaw)
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() throws {
        let task = TaskItem(
            title: "Persist me",
            category: .health,
            priority: .high,
            date: Date(),
            icon: "heart",
            notes: "Important"
        )
        context.insert(task)
        try context.save()

        let descriptor = FetchDescriptor<TaskItem>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "Persist me")
        XCTAssertEqual(fetched.first?.category, .health)
        XCTAssertEqual(fetched.first?.notes, "Important")
    }
}

// MARK: - TaskRecurrence Tests

final class TaskRecurrenceTests: XCTestCase {

    func testNextDateNone() {
        let result = TaskRecurrence.none.nextDate(after: Date())
        XCTAssertNil(result)
    }

    func testNextDateDaily() {
        let now = Date()
        let next = TaskRecurrence.daily.nextDate(after: now)
        XCTAssertNotNil(next)
        let diff = Calendar.current.dateComponents([.day], from: now, to: next!)
        XCTAssertEqual(diff.day, 1)
    }

    func testNextDateWeekly() {
        let now = Date()
        let next = TaskRecurrence.weekly.nextDate(after: now)
        XCTAssertNotNil(next)
        let diff = Calendar.current.dateComponents([.day], from: now, to: next!)
        XCTAssertEqual(diff.day, 7)
    }

    func testNextDateBiweekly() {
        let now = Date()
        let next = TaskRecurrence.biweekly.nextDate(after: now)
        XCTAssertNotNil(next)
        let diff = Calendar.current.dateComponents([.day], from: now, to: next!)
        XCTAssertEqual(diff.day, 14)
    }

    func testNextDateMonthly() {
        let now = Date()
        let next = TaskRecurrence.monthly.nextDate(after: now)
        XCTAssertNotNil(next)
        let diff = Calendar.current.dateComponents([.month], from: now, to: next!)
        XCTAssertEqual(diff.month, 1)
    }

    func testAllCases() {
        XCTAssertEqual(TaskRecurrence.allCases.count, 5)
    }
}
