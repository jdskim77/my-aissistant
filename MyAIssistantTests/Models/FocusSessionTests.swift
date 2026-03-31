import XCTest
import SwiftData
@testable import MyAIssistant

@MainActor
final class FocusSessionTests: XCTestCase {

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
        let session = FocusSession()
        XCTAssertEqual(session.taskTitle, "Focus Session")
        XCTAssertNil(session.taskID)
        XCTAssertEqual(session.workDuration, 25 * 60)
        XCTAssertEqual(session.breakDuration, 5 * 60)
        XCTAssertEqual(session.intervalsTarget, 4)
        XCTAssertEqual(session.intervalsCompleted, 0)
        XCTAssertEqual(session.totalFocusSeconds, 0)
        XCTAssertFalse(session.completed)
        XCTAssertNil(session.endedAt)
        XCTAssertFalse(session.id.isEmpty)
    }

    func testCustomInit() {
        let session = FocusSession(
            taskID: "task-123",
            taskTitle: "Write report",
            workDuration: 50 * 60,
            breakDuration: 10 * 60,
            intervalsTarget: 2
        )
        XCTAssertEqual(session.taskID, "task-123")
        XCTAssertEqual(session.taskTitle, "Write report")
        XCTAssertEqual(session.workDuration, 50 * 60)
        XCTAssertEqual(session.breakDuration, 10 * 60)
        XCTAssertEqual(session.intervalsTarget, 2)
    }

    // MARK: - State Management

    func testCompleteSession() {
        let session = FocusSession()
        session.completed = true
        session.endedAt = Date()
        session.intervalsCompleted = 4
        session.totalFocusSeconds = 100 * 60

        XCTAssertTrue(session.completed)
        XCTAssertNotNil(session.endedAt)
        XCTAssertEqual(session.intervalsCompleted, 4)
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() throws {
        let session = FocusSession(taskTitle: "Deep work", workDuration: 30 * 60)
        session.intervalsCompleted = 2
        session.totalFocusSeconds = 60 * 60
        context.insert(session)
        try context.save()

        let descriptor = FetchDescriptor<FocusSession>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.taskTitle, "Deep work")
        XCTAssertEqual(fetched.first?.intervalsCompleted, 2)
        XCTAssertEqual(fetched.first?.totalFocusSeconds, 60 * 60)
    }
}
