import XCTest
import SwiftData
@testable import MyAIssistant

@MainActor
final class ActivityEntryTests: XCTestCase {

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
        let entry = ActivityEntry(activity: "Completed task", category: "productivity")
        XCTAssertEqual(entry.activity, "Completed task")
        XCTAssertEqual(entry.category, "productivity")
        XCTAssertEqual(entry.source, "chat")
        XCTAssertFalse(entry.id.isEmpty)
    }

    func testCustomInit() {
        let entry = ActivityEntry(
            activity: "Logged mood",
            category: "checkin",
            source: "checkin"
        )
        XCTAssertEqual(entry.source, "checkin")
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() throws {
        let entry = ActivityEntry(
            activity: "Created focus session",
            category: "focus",
            source: "focus"
        )
        context.insert(entry)
        try context.save()

        let descriptor = FetchDescriptor<ActivityEntry>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.activity, "Created focus session")
        XCTAssertEqual(fetched.first?.category, "focus")
    }
}
