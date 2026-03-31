import XCTest
import SwiftData
@testable import MyAIssistant

@MainActor
final class CheckInRecordTests: XCTestCase {

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
        let record = CheckInRecord(timeSlot: .morning)
        XCTAssertEqual(record.timeSlot, .morning)
        XCTAssertEqual(record.timeSlotRaw, "Morning")
        XCTAssertFalse(record.completed)
        XCTAssertNil(record.mood)
        XCTAssertNil(record.energyLevel)
        XCTAssertNil(record.notes)
        XCTAssertNil(record.aiSummary)
        XCTAssertFalse(record.id.isEmpty)
    }

    func testInitWithAllFields() {
        let record = CheckInRecord(
            timeSlot: .night,
            date: Date(),
            completed: true,
            mood: 4,
            energyLevel: 3,
            notes: "Good day",
            aiSummary: "AI summary"
        )
        XCTAssertEqual(record.timeSlot, .night)
        XCTAssertTrue(record.completed)
        XCTAssertEqual(record.mood, 4)
        XCTAssertEqual(record.energyLevel, 3)
        XCTAssertEqual(record.notes, "Good day")
        XCTAssertEqual(record.aiSummary, "AI summary")
    }

    // MARK: - TimeSlot Computed Property

    func testTimeSlotSetterUpdatesRaw() {
        let record = CheckInRecord(timeSlot: .morning)
        record.timeSlot = .afternoon
        XCTAssertEqual(record.timeSlotRaw, "Afternoon")
    }

    func testInvalidTimeSlotFallsBackToMorning() {
        let record = CheckInRecord(timeSlot: .night)
        record.timeSlotRaw = "Invalid"
        XCTAssertEqual(record.timeSlot, .morning)
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() throws {
        let record = CheckInRecord(timeSlot: .midday, completed: true, mood: 5)
        context.insert(record)
        try context.save()

        let descriptor = FetchDescriptor<CheckInRecord>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.timeSlot, .midday)
        XCTAssertEqual(fetched.first?.mood, 5)
        XCTAssertTrue(fetched.first?.completed ?? false)
    }
}

// MARK: - CheckInTime Tests

final class CheckInTimeTests: XCTestCase {

    func testAllCasesCount() {
        XCTAssertEqual(CheckInTime.allCases.count, 4)
    }

    func testHours() {
        XCTAssertEqual(CheckInTime.morning.hour, 8)
        XCTAssertEqual(CheckInTime.midday.hour, 13)
        XCTAssertEqual(CheckInTime.afternoon.hour, 18)
        XCTAssertEqual(CheckInTime.night.hour, 22)
    }

    func testIcons() {
        XCTAssertFalse(CheckInTime.morning.icon.isEmpty)
        XCTAssertFalse(CheckInTime.midday.icon.isEmpty)
        XCTAssertFalse(CheckInTime.afternoon.icon.isEmpty)
        XCTAssertFalse(CheckInTime.night.icon.isEmpty)
    }

    func testTitles() {
        XCTAssertEqual(CheckInTime.morning.title, "Morning Brief")
        XCTAssertEqual(CheckInTime.midday.title, "Midday Check-in")
        XCTAssertEqual(CheckInTime.afternoon.title, "Late Afternoon")
        XCTAssertEqual(CheckInTime.night.title, "Night Wind-down")
    }

    func testGreetings() {
        for time in CheckInTime.allCases {
            XCTAssertFalse(time.greeting.isEmpty, "Greeting for \(time.rawValue) should not be empty")
        }
    }

    func testMotivationTips() {
        for time in CheckInTime.allCases {
            XCTAssertFalse(time.motivationTip.isEmpty, "Motivation tip for \(time.rawValue) should not be empty")
        }
    }

    func testTimeLabels() {
        XCTAssertEqual(CheckInTime.morning.timeLabel, "8:00 AM")
        XCTAssertEqual(CheckInTime.midday.timeLabel, "1:00 PM")
        XCTAssertEqual(CheckInTime.afternoon.timeLabel, "6:00 PM")
        XCTAssertEqual(CheckInTime.night.timeLabel, "10:00 PM")
    }

    func testCurrentReturnsValidCase() {
        let current = CheckInTime.current()
        XCTAssertTrue(CheckInTime.allCases.contains(current))
    }

    func testNextReturnsValidCase() {
        let next = CheckInTime.next()
        XCTAssertTrue(CheckInTime.allCases.contains(next))
    }
}
