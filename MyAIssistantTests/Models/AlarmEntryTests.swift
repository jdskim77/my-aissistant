import XCTest
import SwiftData
@testable import MyAIssistant

@MainActor
final class AlarmEntryTests: XCTestCase {

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
        let alarm = AlarmEntry(label: "Wake up", time: Date())
        XCTAssertEqual(alarm.label, "Wake up")
        XCTAssertFalse(alarm.repeatsDaily)
        XCTAssertFalse(alarm.id.isEmpty)
        XCTAssertFalse(alarm.notificationID.isEmpty)
    }

    func testRepeatingAlarmInit() {
        let alarm = AlarmEntry(label: "Medication", time: Date(), repeatsDaily: true)
        XCTAssertTrue(alarm.repeatsDaily)
    }

    func testCustomNotificationID() {
        let alarm = AlarmEntry(
            label: "Meeting",
            time: Date(),
            notificationID: "custom-notif-id"
        )
        XCTAssertEqual(alarm.notificationID, "custom-notif-id")
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() throws {
        let time = Date()
        let alarm = AlarmEntry(label: "Test Alarm", time: time, repeatsDaily: true)
        context.insert(alarm)
        try context.save()

        let descriptor = FetchDescriptor<AlarmEntry>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.label, "Test Alarm")
        XCTAssertTrue(fetched.first?.repeatsDaily ?? false)
    }

    func testMultipleAlarms() throws {
        let alarm1 = AlarmEntry(label: "Alarm 1", time: Date())
        let alarm2 = AlarmEntry(label: "Alarm 2", time: Date())
        context.insert(alarm1)
        context.insert(alarm2)
        try context.save()

        let descriptor = FetchDescriptor<AlarmEntry>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 2)
    }
}
