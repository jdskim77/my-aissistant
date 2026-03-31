import XCTest
import SwiftData
@testable import MyAIssistant

@MainActor
final class UserProfileTests: XCTestCase {

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
        let profile = UserProfile()
        XCTAssertEqual(profile.displayName, "")
        XCTAssertFalse(profile.onboardingCompleted)
        XCTAssertFalse(profile.notificationsEnabled)
        XCTAssertFalse(profile.calendarSyncEnabled)
        XCTAssertFalse(profile.id.isEmpty)
    }

    func testCustomInit() {
        let profile = UserProfile(
            displayName: "John",
            onboardingCompleted: true,
            notificationsEnabled: true,
            calendarSyncEnabled: true
        )
        XCTAssertEqual(profile.displayName, "John")
        XCTAssertTrue(profile.onboardingCompleted)
        XCTAssertTrue(profile.notificationsEnabled)
        XCTAssertTrue(profile.calendarSyncEnabled)
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() throws {
        let profile = UserProfile(displayName: "Alice", onboardingCompleted: true)
        context.insert(profile)
        try context.save()

        let descriptor = FetchDescriptor<UserProfile>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.displayName, "Alice")
        XCTAssertTrue(fetched.first?.onboardingCompleted ?? false)
    }
}
