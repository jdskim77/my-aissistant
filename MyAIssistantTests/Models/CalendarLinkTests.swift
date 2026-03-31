import XCTest
import SwiftData
@testable import MyAIssistant

@MainActor
final class CalendarLinkTests: XCTestCase {

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

    func testAppleCalendarInit() {
        let link = CalendarLink(source: .apple, calendarID: "cal-123", name: "Personal")
        XCTAssertEqual(link.calendarSource, .apple)
        XCTAssertEqual(link.source, "apple")
        XCTAssertEqual(link.calendarID, "cal-123")
        XCTAssertEqual(link.name, "Personal")
        XCTAssertTrue(link.enabled)
        XCTAssertNil(link.lastSynced)
        XCTAssertEqual(link.color, "#2D5016")
    }

    func testGoogleCalendarInit() {
        let link = CalendarLink(
            source: .google,
            calendarID: "user@gmail.com",
            name: "Work",
            color: "#FF0000",
            enabled: false
        )
        XCTAssertEqual(link.calendarSource, .google)
        XCTAssertEqual(link.source, "google")
        XCTAssertFalse(link.enabled)
        XCTAssertEqual(link.color, "#FF0000")
    }

    // MARK: - Computed Source

    func testCalendarSourceSetter() {
        let link = CalendarLink(source: .apple, calendarID: "test", name: "Test")
        link.calendarSource = .google
        XCTAssertEqual(link.source, "google")
    }

    func testInvalidSourceFallsBackToApple() {
        let link = CalendarLink(source: .google, calendarID: "test", name: "Test")
        link.source = "invalid"
        XCTAssertEqual(link.calendarSource, .apple)
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() throws {
        let link = CalendarLink(source: .google, calendarID: "work@gmail.com", name: "Work Calendar")
        link.lastSynced = Date()
        context.insert(link)
        try context.save()

        let descriptor = FetchDescriptor<CalendarLink>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Work Calendar")
        XCTAssertNotNil(fetched.first?.lastSynced)
    }
}

// MARK: - CalendarSource Tests

final class CalendarSourceTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(CalendarSource.allCases.count, 2)
    }

    func testDisplayNames() {
        XCTAssertEqual(CalendarSource.apple.displayName, "Apple Calendar")
        XCTAssertEqual(CalendarSource.google.displayName, "Google Calendar")
    }

    func testIcons() {
        XCTAssertEqual(CalendarSource.apple.icon, "calendar")
        XCTAssertEqual(CalendarSource.google.icon, "globe")
    }
}
