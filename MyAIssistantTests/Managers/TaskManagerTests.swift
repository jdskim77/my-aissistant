import XCTest
import SwiftData
@testable import MyAIssistant

@MainActor
final class TaskManagerTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var sut: TaskManager!

    override func setUp() async throws {
        container = try TestModelContainer.create()
        context = container.mainContext
        sut = TaskManager(modelContext: context)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        sut = nil
    }

    // MARK: - Helpers

    private func makeTask(
        title: String = "Test Task",
        category: TaskCategory = .personal,
        priority: TaskPriority = .medium,
        date: Date = Date(),
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

    // MARK: - CRUD Tests

    func testAddTask() throws {
        let task = makeTask(title: "New Task")
        sut.addTask(task)

        let tasks = sut.allTasks()
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.title, "New Task")
    }

    func testToggleCompletion() throws {
        let task = makeTask()
        sut.addTask(task)
        XCTAssertFalse(task.done)
        XCTAssertNil(task.completedAt)

        sut.toggleCompletion(task)
        XCTAssertTrue(task.done)
        XCTAssertNotNil(task.completedAt)

        sut.toggleCompletion(task)
        XCTAssertFalse(task.done)
        XCTAssertNil(task.completedAt)
    }

    func testToggleCompletionRecurringDoesNotDuplicateOnReToggle() throws {
        // P1 bug: toggling a recurring task done -> undone -> done again
        // (e.g. an accidental double-tap / undo) inserted a SECOND clone of
        // the next occurrence, since the recurrence-generation block only
        // keyed off `task.done` flipping true with no de-dup check.
        let task = makeTask(title: "Daily Standup", date: Date())
        task.recurrence = .daily
        sut.addTask(task)

        // First completion: generates exactly one next-occurrence clone.
        sut.toggleCompletion(task)
        XCTAssertTrue(task.done)
        XCTAssertEqual(sut.allTasks().count, 2, "expected original + 1 clone after first completion")

        // Undo, then redo the completion on the SAME task/date/recurrence.
        sut.toggleCompletion(task) // -> undone
        XCTAssertFalse(task.done)
        sut.toggleCompletion(task) // -> done again
        XCTAssertTrue(task.done)

        let clones = sut.allTasks().filter { $0.title == "Daily Standup" && $0.id != task.id }
        XCTAssertEqual(clones.count, 1, "re-toggling done should not insert a duplicate recurring clone")
    }

    func testToggleCompletionRecurringSuccessorEditDoesNotCauseDuplicate() throws {
        // Codex review of the first fix caught this: the generated
        // successor's id is derived from the SOURCE task's own id, not
        // from the successor's own (editable) title/category/date, so
        // renaming/recategorizing/rescheduling the successor must NOT
        // defeat the de-dup check on re-toggle of the original.
        let task = makeTask(title: "Daily Standup", date: Date())
        task.recurrence = .daily
        sut.addTask(task)

        sut.toggleCompletion(task) // -> done, generates successor
        XCTAssertEqual(sut.allTasks().count, 2)

        let successor = sut.allTasks().first { $0.id != task.id }
        successor?.title = "Renamed"
        successor?.category = .work
        successor?.date = Calendar.current.date(byAdding: .day, value: 5, to: Date())!

        sut.toggleCompletion(task) // -> undone
        sut.toggleCompletion(task) // -> done again

        XCTAssertEqual(sut.allTasks().count, 2, "editing the successor must not defeat de-dup on re-toggle")
    }

    func testToggleCompletionRecurringDoesNotCollideWithUnrelatedIdenticalTask() throws {
        // Codex review: two independent recurring tasks with identical
        // title/category/date/recurrence must each get their own
        // successor — matching on those editable fields would silently
        // drop the second task's legitimate successor.
        let taskA = makeTask(title: "Daily Standup", category: .work, date: Date())
        taskA.recurrence = .daily
        let taskB = makeTask(title: "Daily Standup", category: .work, date: Date())
        taskB.recurrence = .daily
        sut.addTask(taskA)
        sut.addTask(taskB)

        sut.toggleCompletion(taskA)
        sut.toggleCompletion(taskB)

        XCTAssertEqual(sut.allTasks().count, 4, "each independent task must get its own successor")
    }

    func testDeleteTask() throws {
        let task = makeTask()
        sut.addTask(task)
        XCTAssertEqual(sut.allTasks().count, 1)

        sut.deleteTask(task)
        XCTAssertEqual(sut.allTasks().count, 0)
    }

    // MARK: - Query Tests

    func testTodayTasks() throws {
        let today = makeTask(title: "Today", date: Date())
        let yesterday = makeTask(
            title: "Yesterday",
            date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        )
        let tomorrow = makeTask(
            title: "Tomorrow",
            date: Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        )

        sut.addTask(today)
        sut.addTask(yesterday)
        sut.addTask(tomorrow)

        let todayTasks = sut.todayTasks()
        XCTAssertEqual(todayTasks.count, 1)
        XCTAssertEqual(todayTasks.first?.title, "Today")
    }

    func testUpcomingTasks() throws {
        let past = makeTask(
            title: "Past",
            date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        )
        let future = makeTask(
            title: "Future",
            date: Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        )
        let doneToday = makeTask(title: "Done", date: Date(), done: true)

        sut.addTask(past)
        sut.addTask(future)
        sut.addTask(doneToday)

        let upcoming = sut.upcomingTasks()
        // Should include undone tasks from today onwards, not past or done
        XCTAssertTrue(upcoming.contains(where: { $0.title == "Future" }))
        XCTAssertFalse(upcoming.contains(where: { $0.title == "Past" }))
        XCTAssertFalse(upcoming.contains(where: { $0.title == "Done" }))
    }

    func testHighPriorityUpcoming() throws {
        let highTask = makeTask(title: "High", priority: .high, date: Date())
        let lowTask = makeTask(title: "Low", priority: .low, date: Date())

        sut.addTask(highTask)
        sut.addTask(lowTask)

        let highPriority = sut.highPriorityUpcoming()
        XCTAssertEqual(highPriority.count, 1)
        XCTAssertEqual(highPriority.first?.title, "High")
    }

    func testTasksGroupedByDate() throws {
        let today = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        sut.addTask(makeTask(title: "Today 1", date: today))
        sut.addTask(makeTask(title: "Today 2", date: today))
        sut.addTask(makeTask(title: "Tomorrow 1", date: tomorrow))

        let grouped = sut.tasksGroupedByDate()
        XCTAssertEqual(grouped.count, 2)
    }

    func testTasksGroupedByDateFilteredByCategory() throws {
        sut.addTask(makeTask(title: "Work", category: .work, date: Date()))
        sut.addTask(makeTask(title: "Personal", category: .personal, date: Date()))

        let workOnly = sut.tasksGroupedByDate(category: .work)
        let allWork = workOnly.flatMap(\.tasks)
        XCTAssertEqual(allWork.count, 1)
        XCTAssertEqual(allWork.first?.title, "Work")
    }

    // MARK: - Stats Tests

    func testCompletionRate() throws {
        sut.addTask(makeTask(title: "Done 1", done: true))
        sut.addTask(makeTask(title: "Done 2", done: true))
        sut.addTask(makeTask(title: "Not Done"))

        let rate = sut.completionRate()
        XCTAssertEqual(rate, 66) // 2/3 ≈ 66%
    }

    func testCompletionRateEmpty() throws {
        let rate = sut.completionRate()
        XCTAssertEqual(rate, 0)
    }

    func testCompletedTodayCount() throws {
        sut.addTask(makeTask(title: "Done", done: true))
        sut.addTask(makeTask(title: "Not Done"))

        XCTAssertEqual(sut.completedTodayCount, 1)
        XCTAssertEqual(sut.todayTaskCount, 2)
    }

    // MARK: - Calendar Sync Tests

    func testIsCalendarImported() throws {
        let regular = makeTask()
        let imported = makeTask()
        imported.externalCalendarID = "google:abc123"

        XCTAssertFalse(sut.isCalendarImported(regular))
        XCTAssertTrue(sut.isCalendarImported(imported))
    }

    func testCalendarSourceLabel() throws {
        let regular = makeTask()
        let google = makeTask()
        google.externalCalendarID = "google:abc123"
        let apple = makeTask()
        apple.externalCalendarID = "ekid:xyz"

        XCTAssertNil(sut.calendarSourceLabel(regular))
        XCTAssertEqual(sut.calendarSourceLabel(google), "Google")
        XCTAssertEqual(sut.calendarSourceLabel(apple), "Calendar")
    }

    // MARK: - AI Context Tests

    func testScheduleSummary() throws {
        let task = makeTask(title: "My Task", category: .work, priority: .high)
        sut.addTask(task)

        let summary = sut.scheduleSummary()
        XCTAssertTrue(summary.contains("My Task"))
        XCTAssertTrue(summary.contains("[High]"))
        XCTAssertTrue(summary.contains("(Work)"))
        XCTAssertTrue(summary.contains("○")) // not done
    }

    func testScheduleSummaryCompletedTask() throws {
        let task = makeTask(title: "Done Task", done: true)
        sut.addTask(task)

        let summary = sut.scheduleSummary()
        XCTAssertTrue(summary.contains("✓")) // done
    }
}
