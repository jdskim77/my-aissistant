import XCTest
import SwiftData
@testable import MyAIssistant

@MainActor
final class DataSeederTests: XCTestCase {

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

    // MARK: - Seed Behavior

    func testSeedIfEmptyPopulatesTasksInDebug() {
        // In DEBUG builds, seedIfEmpty should insert sample data
        DataSeeder.seedIfEmpty(context: context)

        let taskDescriptor = FetchDescriptor<TaskItem>()
        let tasks = (try? context.fetch(taskDescriptor)) ?? []

        #if DEBUG
        XCTAssertGreaterThan(tasks.count, 0, "Debug builds should seed sample tasks")
        #else
        XCTAssertEqual(tasks.count, 0, "Release builds should not seed data")
        #endif
    }

    func testSeedIfEmptyPopulatesCheckInsInDebug() {
        DataSeeder.seedIfEmpty(context: context)

        let checkInDescriptor = FetchDescriptor<CheckInRecord>()
        let checkIns = (try? context.fetch(checkInDescriptor)) ?? []

        #if DEBUG
        XCTAssertGreaterThan(checkIns.count, 0, "Debug builds should seed sample check-ins")
        #else
        XCTAssertEqual(checkIns.count, 0, "Release builds should not seed data")
        #endif
    }

    func testSeedDoesNotDuplicateOnSecondCall() {
        DataSeeder.seedIfEmpty(context: context)
        let firstCount = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).count

        // Call again — should not insert more
        DataSeeder.seedIfEmpty(context: context)
        let secondCount = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).count

        XCTAssertEqual(firstCount, secondCount, "Calling seedIfEmpty twice should not duplicate data")
    }

    func testSeedDoesNotRunWhenDataExists() throws {
        // Insert a task first
        let existing = TaskItem(
            title: "Existing",
            category: .personal,
            priority: .medium,
            date: Date(),
            icon: "star"
        )
        context.insert(existing)
        try context.save()

        DataSeeder.seedIfEmpty(context: context)

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(tasks.count, 1, "Seeder should not run when data already exists")
        XCTAssertEqual(tasks.first?.title, "Existing")
    }

    // MARK: - Seed Data Quality (Debug only)

    func testSeededTasksHaveRequiredFields() {
        DataSeeder.seedIfEmpty(context: context)

        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        for task in tasks {
            XCTAssertFalse(task.title.isEmpty, "Seeded task should have a title")
            XCTAssertFalse(task.icon.isEmpty, "Seeded task should have an icon")
            XCTAssertFalse(task.id.isEmpty, "Seeded task should have an id")
        }
    }

    func testSeededCheckInsHaveTimeSlots() {
        DataSeeder.seedIfEmpty(context: context)

        let checkIns = (try? context.fetch(FetchDescriptor<CheckInRecord>())) ?? []
        for record in checkIns {
            XCTAssertTrue(
                CheckInTime.allCases.contains(record.timeSlot),
                "Seeded check-in should have a valid time slot"
            )
        }
    }
}
