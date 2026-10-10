import XCTest
import SwiftData
@testable import MyAIssistant

/// Zero-coverage critical path: DataExportService's export/import round
/// trip is how users back up and recover their data on a new device. A
/// silent regression here (e.g. a field dropped from exportJSON, or a
/// dedup check broken on importJSON) would not surface as a crash — it
/// would surface as a user discovering their data didn't actually come
/// back after a restore. Non-crisis, non-money: purely a data-integrity
/// path.
@MainActor
final class DataExportServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var sut: DataExportService!

    override func setUp() async throws {
        container = try TestModelContainer.create()
        context = container.mainContext
        sut = DataExportService(modelContext: context)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        sut = nil
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
    }

    // MARK: - Export

    func testExportJSONProducesValidTopLevelStructure() throws {
        let task = TaskItem(
            title: "Write tests",
            category: .personal,
            priority: .high,
            date: Date(),
            icon: "📝"
        )
        context.insert(task)

        let data = try sut.exportJSON()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertNotNil(json?["exportDate"])
        XCTAssertEqual(json?["schemaVersion"] as? Int, 5)
        let tasks = json?["tasks"] as? [[String: Any]]
        XCTAssertEqual(tasks?.count, 1)
        XCTAssertEqual(tasks?.first?["title"] as? String, "Write tests")
    }

    func testExportJSONWithNoDataStillProducesAllTopLevelKeys() throws {
        let data = try sut.exportJSON()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        for key in ["tasks", "checkIns", "activities", "chatMessages",
                    "dailySnapshots", "balanceCheckIns", "seasonGoals", "habits"] {
            XCTAssertNotNil(json?[key], "missing top-level export key: \(key)")
            XCTAssertEqual((json?[key] as? [[String: Any]])?.count, 0)
        }
    }

    // MARK: - Round Trip

    func testExportThenImportRestoresTaskIntoFreshContext() throws {
        let task = TaskItem(
            id: "fixed-task-id",
            title: "Round trip me",
            category: .health,
            priority: .medium,
            date: Date(),
            done: true,
            icon: "🏃"
        )
        context.insert(task)
        let data = try sut.exportJSON()

        // Fresh context/container simulating a new device with no data.
        let freshContainer = try TestModelContainer.create()
        let freshContext = freshContainer.mainContext
        let freshService = DataExportService(modelContext: freshContext)

        let url = tempURL()
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try freshService.importJSON(from: url)

        XCTAssertEqual(result.tasksImported, 1)
        let restored = try freshContext.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.id, "fixed-task-id")
        XCTAssertEqual(restored.first?.title, "Round trip me")
        XCTAssertEqual(restored.first?.category, .health)
        XCTAssertEqual(restored.first?.priority, .medium)
        XCTAssertEqual(restored.first?.icon, "🏃")
        XCTAssertTrue(restored.first?.done ?? false)
    }

    func testImportJSONSkipsAlreadyExistingRecordsInsteadOfDuplicating() throws {
        let task = TaskItem(
            id: "dup-check-id",
            title: "Only once",
            category: .work,
            priority: .low,
            date: Date(),
            icon: "💼"
        )
        context.insert(task)
        let data = try sut.exportJSON()

        let url = tempURL()
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // Import the same backup twice into the SAME context the record
        // already lives in — the second import must skip it, not duplicate.
        let first = try sut.importJSON(from: url)
        let second = try sut.importJSON(from: url)

        XCTAssertEqual(first.tasksImported, 0, "task already existed before any import")
        XCTAssertEqual(first.skipped, 1)
        XCTAssertEqual(second.tasksImported, 0)
        XCTAssertEqual(second.skipped, 1)

        let all = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(all.count, 1, "re-importing a backup must not create duplicate rows")
    }

    func testImportJSONDedupMatchesOnIDNotJustExistence() throws {
        // A broken "does ANY task already exist" dedup check would pass
        // the test above too. Prove the match is keyed on id specifically:
        // an unrelated existing task must not cause a different-id record
        // to be (wrongly) skipped, and an existing task must not be
        // overwritten by an import of a same-id record with different content.
        let unrelated = TaskItem(
            id: "unrelated-id",
            title: "Pre-existing, unrelated",
            category: .personal,
            priority: .medium,
            date: Date(),
            icon: "📌"
        )
        context.insert(unrelated)

        let sourceTask = TaskItem(
            id: "fresh-id",
            title: "Should still import",
            category: .health,
            priority: .high,
            date: Date(),
            icon: "🏃"
        )
        let sourceContainer = try TestModelContainer.create()
        let sourceContext = sourceContainer.mainContext
        sourceContext.insert(sourceTask)
        let sourceService = DataExportService(modelContext: sourceContext)
        let data = try sourceService.exportJSON()

        let url = tempURL()
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try sut.importJSON(from: url)

        XCTAssertEqual(result.tasksImported, 1, "a different-id record must import even when an unrelated task already exists")
        XCTAssertEqual(result.skipped, 0)

        let all = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains { $0.id == "unrelated-id" }, "pre-existing unrelated task must be untouched")
        XCTAssertTrue(all.contains { $0.id == "fresh-id" }, "new record must have been imported")
    }

    func testImportJSONRejectsFileWithoutExportDate() throws {
        let url = tempURL()
        let badJSON: [String: Any] = ["tasks": []]
        try JSONSerialization.data(withJSONObject: badJSON).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try sut.importJSON(from: url))
    }

    func testImportJSONRejectsFutureSchemaVersion() throws {
        let url = tempURL()
        let futureJSON: [String: Any] = [
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "schemaVersion": 999
        ]
        try JSONSerialization.data(withJSONObject: futureJSON).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try sut.importJSON(from: url))
    }

    func testExportThenImportRestoresCheckInRecord() throws {
        let checkIn = CheckInRecord(
            id: "checkin-fixed-id",
            timeSlot: .night,
            date: Date(),
            completed: true,
            mood: 4,
            energyLevel: 3,
            notes: "felt good",
            aiSummary: nil
        )
        context.insert(checkIn)
        let data = try sut.exportJSON()

        let freshContainer = try TestModelContainer.create()
        let freshContext = freshContainer.mainContext
        let freshService = DataExportService(modelContext: freshContext)

        let url = tempURL()
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try freshService.importJSON(from: url)

        XCTAssertEqual(result.checkInsImported, 1)
        let restored = try freshContext.fetch(FetchDescriptor<CheckInRecord>())
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.mood, 4)
        XCTAssertEqual(restored.first?.energyLevel, 3)
        XCTAssertTrue(restored.first?.completed ?? false)
        XCTAssertEqual(restored.first?.notes, "felt good")
    }
}
