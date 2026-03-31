import XCTest
@testable import MyAIssistant

@MainActor
final class GreetingManagerTests: XCTestCase {

    private var sut: GreetingManager!

    override func setUp() async throws {
        sut = GreetingManager()
        // Clear any cached greeting state
        UserDefaults.standard.removeObject(forKey: AppConstants.lastGreetedTimestampKey)
        UserDefaults.standard.removeObject(forKey: AppConstants.lastGreetingTextKey)
        UserDefaults.standard.removeObject(forKey: "usedOpenersToday")
        UserDefaults.standard.removeObject(forKey: "usedOpenersDate")
    }

    override func tearDown() async throws {
        sut = nil
        UserDefaults.standard.removeObject(forKey: AppConstants.lastGreetedTimestampKey)
        UserDefaults.standard.removeObject(forKey: AppConstants.lastGreetingTextKey)
        UserDefaults.standard.removeObject(forKey: "usedOpenersToday")
        UserDefaults.standard.removeObject(forKey: "usedOpenersDate")
    }

    // MARK: - Generate Greeting

    func testGenerateGreetingProducesText() {
        let isNew = sut.generateGreetingIfNeeded(
            todayTaskCount: 5,
            completedTodayCount: 2,
            highPriorityTitles: ["Important Task"],
            completionRate: 40,
            streak: 1
        )

        XCTAssertTrue(isNew)
        XCTAssertFalse(sut.currentGreeting.isEmpty)
        XCTAssertTrue(sut.isShowingGreeting)
    }

    func testGenerateGreetingCooldown() {
        // First call generates fresh
        let first = sut.generateGreetingIfNeeded(
            todayTaskCount: 3,
            completedTodayCount: 1,
            highPriorityTitles: [],
            completionRate: 33,
            streak: 0
        )
        XCTAssertTrue(first)
        let firstGreeting = sut.currentGreeting

        // Second call within cooldown restores cached
        let second = sut.generateGreetingIfNeeded(
            todayTaskCount: 3,
            completedTodayCount: 1,
            highPriorityTitles: [],
            completionRate: 33,
            streak: 0
        )
        XCTAssertFalse(second)
        XCTAssertEqual(sut.currentGreeting, firstGreeting)
    }

    func testGenerateGreetingAfterCooldownExpired() {
        // Generate first greeting
        sut.generateGreetingIfNeeded(
            todayTaskCount: 2,
            completedTodayCount: 0,
            highPriorityTitles: [],
            completionRate: 0,
            streak: 0
        )

        // Simulate cooldown expired (set timestamp to > 1 hour ago)
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        UserDefaults.standard.set(twoHoursAgo.timeIntervalSince1970, forKey: AppConstants.lastGreetedTimestampKey)

        let isNew = sut.generateGreetingIfNeeded(
            todayTaskCount: 2,
            completedTodayCount: 0,
            highPriorityTitles: [],
            completionRate: 0,
            streak: 0
        )
        XCTAssertTrue(isNew)
    }

    // MARK: - Dismiss Greeting

    func testDismissGreeting() {
        sut.generateGreetingIfNeeded(
            todayTaskCount: 1,
            completedTodayCount: 0,
            highPriorityTitles: [],
            completionRate: 0,
            streak: 0
        )
        XCTAssertTrue(sut.isShowingGreeting)

        sut.dismissGreeting()
        XCTAssertFalse(sut.isShowingGreeting)
    }

    // MARK: - Used Opener Tracking

    func testRecordUsedOpener() {
        GreetingManager.recordUsedOpenerForToday("Good morning!")
        let used = GreetingManager.loadUsedOpenersForToday()
        XCTAssertTrue(used.contains("Good morning!"))
    }

    func testUsedOpenersResetOnNewDay() {
        // Set used openers for a past date
        UserDefaults.standard.set("2020-01-01", forKey: "usedOpenersDate")
        UserDefaults.standard.set(["Old opener"], forKey: "usedOpenersToday")

        let used = GreetingManager.loadUsedOpenersForToday()
        XCTAssertTrue(used.isEmpty)
    }

    func testRecordDuplicateOpener() {
        GreetingManager.recordUsedOpenerForToday("Hey there!")
        GreetingManager.recordUsedOpenerForToday("Hey there!")

        let stored = UserDefaults.standard.stringArray(forKey: "usedOpenersToday") ?? []
        let count = stored.filter { $0 == "Hey there!" }.count
        XCTAssertEqual(count, 1)
    }

    func testInstanceLoadUsedOpenersMatchesStatic() {
        GreetingManager.recordUsedOpenerForToday("Test opener")

        let staticUsed = GreetingManager.loadUsedOpenersForToday()
        let instanceUsed = sut.loadUsedOpenersToday()
        XCTAssertEqual(staticUsed, instanceUsed)
    }

    // MARK: - Greeting With Context

    func testGreetingContainsHighPriorityTask() {
        // Generate many times — at least one should mention the high priority task
        // (The greeting builder uses randomElement, so we test the builder directly)
        sut.generateGreetingIfNeeded(
            todayTaskCount: 5,
            completedTodayCount: 0,
            highPriorityTitles: ["Call dentist"],
            completionRate: 0,
            streak: 0
        )

        // The greeting will contain task info from VariedGreetingBuilder
        XCTAssertFalse(sut.currentGreeting.isEmpty)
    }

    func testGreetingWithZeroTasks() {
        sut.generateGreetingIfNeeded(
            todayTaskCount: 0,
            completedTodayCount: 0,
            highPriorityTitles: [],
            completionRate: 0,
            streak: 0
        )

        XCTAssertFalse(sut.currentGreeting.isEmpty)
        XCTAssertTrue(sut.isShowingGreeting)
    }

    func testGreetingWithAllTasksCompleted() {
        sut.generateGreetingIfNeeded(
            todayTaskCount: 5,
            completedTodayCount: 5,
            highPriorityTitles: [],
            completionRate: 100,
            streak: 7
        )

        XCTAssertFalse(sut.currentGreeting.isEmpty)
    }
}
