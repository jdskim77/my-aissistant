import XCTest
import SwiftData
@testable import MyAIssistant

@MainActor
final class CheckInManagerTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var sut: CheckInManager!

    override func setUp() async throws {
        container = try TestModelContainer.create()
        context = container.mainContext
        sut = CheckInManager(modelContext: context)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        sut = nil
    }

    // MARK: - Start Check-in

    func testStartCheckInCreatesRecord() {
        let record = sut.startCheckIn(timeSlot: .morning)
        XCTAssertEqual(record.timeSlot, .morning)
        XCTAssertFalse(record.completed)
        XCTAssertNil(record.mood)
    }

    func testStartCheckInPersists() throws {
        _ = sut.startCheckIn(timeSlot: .afternoon)

        let descriptor = FetchDescriptor<CheckInRecord>()
        let all = try context.fetch(descriptor)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.timeSlot, .afternoon)
    }

    func testStartMultipleCheckIns() {
        _ = sut.startCheckIn(timeSlot: .morning)
        _ = sut.startCheckIn(timeSlot: .midday)
        _ = sut.startCheckIn(timeSlot: .afternoon)

        let descriptor = FetchDescriptor<CheckInRecord>()
        let all = (try? context.fetch(descriptor)) ?? []
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - Complete Check-in

    func testCompleteCheckIn() {
        let record = sut.startCheckIn(timeSlot: .morning)
        sut.completeCheckIn(record, mood: 4, energyLevel: 3, notes: "Feeling good", aiSummary: "Great start!")

        XCTAssertTrue(record.completed)
        XCTAssertEqual(record.mood, 4)
        XCTAssertEqual(record.energyLevel, 3)
        XCTAssertEqual(record.notes, "Feeling good")
        XCTAssertEqual(record.aiSummary, "Great start!")
    }

    func testCompleteCheckInWithNilOptionals() {
        let record = sut.startCheckIn(timeSlot: .night)
        sut.completeCheckIn(record, mood: 3, energyLevel: nil, notes: nil, aiSummary: nil)

        XCTAssertTrue(record.completed)
        XCTAssertEqual(record.mood, 3)
        XCTAssertNil(record.energyLevel)
        XCTAssertNil(record.notes)
        XCTAssertNil(record.aiSummary)
    }

    // MARK: - Today Check-ins Query

    func testTodayCheckInsReturnsOnlyToday() {
        // Add today's check-in
        _ = sut.startCheckIn(timeSlot: .morning)

        // Add yesterday's check-in manually
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let oldRecord = CheckInRecord(timeSlot: .morning, date: yesterday)
        context.insert(oldRecord)
        try? context.save()

        let todayRecords = sut.todayCheckIns()
        XCTAssertEqual(todayRecords.count, 1)
        XCTAssertEqual(todayRecords.first?.timeSlot, .morning)
    }

    func testTodayCheckInsEmptyWhenNone() {
        let records = sut.todayCheckIns()
        XCTAssertTrue(records.isEmpty)
    }

    // MARK: - Is Check-in Completed

    func testIsCheckInCompletedFalseWhenNone() {
        XCTAssertFalse(sut.isCheckInCompleted(.morning))
    }

    func testIsCheckInCompletedFalseWhenStartedButNotCompleted() {
        _ = sut.startCheckIn(timeSlot: .morning)
        XCTAssertFalse(sut.isCheckInCompleted(.morning))
    }

    func testIsCheckInCompletedTrueWhenCompleted() {
        let record = sut.startCheckIn(timeSlot: .morning)
        sut.completeCheckIn(record, mood: 4, energyLevel: nil, notes: nil, aiSummary: nil)
        XCTAssertTrue(sut.isCheckInCompleted(.morning))
    }

    func testIsCheckInCompletedSpecificToTimeSlot() {
        let record = sut.startCheckIn(timeSlot: .morning)
        sut.completeCheckIn(record, mood: 4, energyLevel: nil, notes: nil, aiSummary: nil)

        XCTAssertTrue(sut.isCheckInCompleted(.morning))
        XCTAssertFalse(sut.isCheckInCompleted(.afternoon))
        XCTAssertFalse(sut.isCheckInCompleted(.night))
    }

    // MARK: - Recent Check-ins

    func testRecentCheckInsReturnsOnlyCompleted() {
        let record1 = sut.startCheckIn(timeSlot: .morning)
        sut.completeCheckIn(record1, mood: 4, energyLevel: nil, notes: nil, aiSummary: nil)

        _ = sut.startCheckIn(timeSlot: .midday) // not completed

        let recent = sut.recentCheckIns()
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.timeSlot, .morning)
    }

    func testRecentCheckInsRespectsLimit() {
        for slot in CheckInTime.allCases {
            let record = sut.startCheckIn(timeSlot: slot)
            sut.completeCheckIn(record, mood: 3, energyLevel: nil, notes: nil, aiSummary: nil)
        }

        let recent = sut.recentCheckIns(limit: 2)
        XCTAssertEqual(recent.count, 2)
    }

    func testRecentCheckInsOrderedByDateDescending() {
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!

        let old = CheckInRecord(timeSlot: .morning, date: yesterday, completed: true, mood: 3)
        context.insert(old)

        let record = sut.startCheckIn(timeSlot: .afternoon)
        sut.completeCheckIn(record, mood: 5, energyLevel: nil, notes: nil, aiSummary: nil)

        let recent = sut.recentCheckIns()
        XCTAssertEqual(recent.count, 2)
        // Most recent first
        XCTAssertEqual(recent.first?.mood, 5)
    }

    // MARK: - AI Greeting Fallback

    func testGenerateGreetingFallbackOnError() async {
        // Using a real keychain with no key should trigger the fallback
        let mockKeychain = MockKeychainService()
        // No API key set, so it will throw and fall back to timeSlot.greeting

        let greeting = await sut.generateGreeting(
            timeSlot: .morning,
            mood: nil,
            keychain: mockKeychain,
            tier: .free,
            scheduleSummary: "",
            completionRate: 0,
            streak: 0
        )

        XCTAssertEqual(greeting, CheckInTime.morning.greeting)
    }

    func testGenerateGreetingFallbackForNight() async {
        let mockKeychain = MockKeychainService()

        let greeting = await sut.generateGreeting(
            timeSlot: .night,
            mood: 4,
            keychain: mockKeychain,
            tier: .free,
            scheduleSummary: "Some tasks",
            completionRate: 50,
            streak: 2
        )

        XCTAssertEqual(greeting, CheckInTime.night.greeting)
    }
}
