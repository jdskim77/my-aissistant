import XCTest
import SwiftData
@testable import MyAIssistant

@MainActor
final class DailySnapshotTests: XCTestCase {

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
        let snapshot = DailySnapshot(date: Date())
        XCTAssertEqual(snapshot.tasksTotal, 0)
        XCTAssertEqual(snapshot.tasksCompleted, 0)
        XCTAssertEqual(snapshot.checkInsCompleted, 0)
        XCTAssertEqual(snapshot.checkInsTotal, 4)
        XCTAssertNil(snapshot.averageMood)
        XCTAssertEqual(snapshot.streakCount, 0)
        XCTAssertFalse(snapshot.id.isEmpty)
    }

    func testFullInit() {
        let snapshot = DailySnapshot(
            date: Date(),
            tasksTotal: 10,
            tasksCompleted: 7,
            checkInsCompleted: 3,
            checkInsTotal: 4,
            averageMood: 3.5,
            streakCount: 5
        )
        XCTAssertEqual(snapshot.tasksTotal, 10)
        XCTAssertEqual(snapshot.tasksCompleted, 7)
        XCTAssertEqual(snapshot.checkInsCompleted, 3)
        XCTAssertEqual(snapshot.averageMood, 3.5)
        XCTAssertEqual(snapshot.streakCount, 5)
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() throws {
        let snapshot = DailySnapshot(
            date: Date(),
            tasksTotal: 5,
            tasksCompleted: 3,
            averageMood: 4.2,
            streakCount: 2
        )
        context.insert(snapshot)
        try context.save()

        let descriptor = FetchDescriptor<DailySnapshot>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.tasksTotal, 5)
        XCTAssertEqual(fetched.first?.tasksCompleted, 3)
        XCTAssertEqual(fetched.first?.averageMood, 4.2, accuracy: 0.01)
    }

    func testNilAverageMoodPersistence() throws {
        let snapshot = DailySnapshot(date: Date())
        context.insert(snapshot)
        try context.save()

        let descriptor = FetchDescriptor<DailySnapshot>()
        let fetched = try context.fetch(descriptor)
        XCTAssertNil(fetched.first?.averageMood)
    }
}
