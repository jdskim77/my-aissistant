import XCTest
import SwiftData
@testable import MyAIssistant

@MainActor
final class UsageTrackerTests: XCTestCase {

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
        let tracker = UsageTracker()
        XCTAssertEqual(tracker.id, "usage-singleton")
        XCTAssertEqual(tracker.chatMessagesThisMonth, 0)
        XCTAssertEqual(tracker.checkInsThisWeek, 0)
        XCTAssertEqual(tracker.totalInputTokens, 0)
        XCTAssertEqual(tracker.totalOutputTokens, 0)
        XCTAssertFalse(tracker.monthKey.isEmpty)
        XCTAssertFalse(tracker.weekKey.isEmpty)
    }

    // MARK: - Period Keys

    func testMonthKeyFormat() {
        let key = UsageTracker.monthKey(for: Date())
        // Should match yyyy-MM
        let regex = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}$"#)
        let range = NSRange(key.startIndex..., in: key)
        XCTAssertNotNil(regex.firstMatch(in: key, range: range), "monthKey '\(key)' should match yyyy-MM")
    }

    func testWeekKeyFormat() {
        let key = UsageTracker.weekKey(for: Date())
        // Should match yyyy-Wnn
        let regex = try! NSRegularExpression(pattern: #"^\d{4}-W\d{2}$"#)
        let range = NSRange(key.startIndex..., in: key)
        XCTAssertNotNil(regex.firstMatch(in: key, range: range), "weekKey '\(key)' should match yyyy-Wnn")
    }

    // MARK: - Record Chat Message

    func testRecordChatMessage() {
        let tracker = UsageTracker()
        tracker.recordChatMessage(inputTokens: 100, outputTokens: 50)

        XCTAssertEqual(tracker.chatMessagesThisMonth, 1)
        XCTAssertEqual(tracker.totalInputTokens, 100)
        XCTAssertEqual(tracker.totalOutputTokens, 50)
    }

    func testRecordMultipleChatMessages() {
        let tracker = UsageTracker()
        tracker.recordChatMessage(inputTokens: 100, outputTokens: 50)
        tracker.recordChatMessage(inputTokens: 200, outputTokens: 100)

        XCTAssertEqual(tracker.chatMessagesThisMonth, 2)
        XCTAssertEqual(tracker.totalInputTokens, 300)
        XCTAssertEqual(tracker.totalOutputTokens, 150)
    }

    // MARK: - Record Check-In

    func testRecordCheckIn() {
        let tracker = UsageTracker()
        tracker.recordCheckIn()

        XCTAssertEqual(tracker.checkInsThisWeek, 1)
    }

    // MARK: - Limit Checks

    func testFreeTierCanSendChatInitially() {
        let tracker = UsageTracker()
        XCTAssertTrue(tracker.canSendChat(tier: .free))
    }

    func testFreeTierBlockedAfterLimit() {
        let tracker = UsageTracker()
        for _ in 0..<AppConstants.freeChatMessagesPerMonth {
            tracker.recordChatMessage(inputTokens: 10, outputTokens: 5)
        }
        XCTAssertFalse(tracker.canSendChat(tier: .free))
    }

    func testProTierAlwaysCanSendChat() {
        let tracker = UsageTracker()
        for _ in 0..<50 {
            tracker.recordChatMessage(inputTokens: 10, outputTokens: 5)
        }
        XCTAssertTrue(tracker.canSendChat(tier: .pro))
    }

    func testStudentTierAlwaysCanSendChat() {
        let tracker = UsageTracker()
        for _ in 0..<50 {
            tracker.recordChatMessage(inputTokens: 10, outputTokens: 5)
        }
        XCTAssertTrue(tracker.canSendChat(tier: .student))
    }

    func testPowerUserTierAlwaysCanSendChat() {
        let tracker = UsageTracker()
        for _ in 0..<50 {
            tracker.recordChatMessage(inputTokens: 10, outputTokens: 5)
        }
        XCTAssertTrue(tracker.canSendChat(tier: .powerUser))
    }

    func testFreeTierCanDoCheckInInitially() {
        let tracker = UsageTracker()
        XCTAssertTrue(tracker.canDoCheckIn(tier: .free))
    }

    func testFreeTierBlockedAfterCheckInLimit() {
        let tracker = UsageTracker()
        for _ in 0..<AppConstants.freeCheckInsPerWeek {
            tracker.recordCheckIn()
        }
        XCTAssertFalse(tracker.canDoCheckIn(tier: .free))
    }

    func testProTierAlwaysCanCheckIn() {
        let tracker = UsageTracker()
        for _ in 0..<20 {
            tracker.recordCheckIn()
        }
        XCTAssertTrue(tracker.canDoCheckIn(tier: .pro))
    }

    // MARK: - Remaining Counts

    func testRemainingChatMessages() {
        let tracker = UsageTracker()
        XCTAssertEqual(tracker.remainingChatMessages, AppConstants.freeChatMessagesPerMonth)

        tracker.recordChatMessage(inputTokens: 10, outputTokens: 5)
        XCTAssertEqual(tracker.remainingChatMessages, AppConstants.freeChatMessagesPerMonth - 1)
    }

    func testRemainingCheckIns() {
        let tracker = UsageTracker()
        XCTAssertEqual(tracker.remainingCheckIns, AppConstants.freeCheckInsPerWeek)

        tracker.recordCheckIn()
        XCTAssertEqual(tracker.remainingCheckIns, AppConstants.freeCheckInsPerWeek - 1)
    }

    func testRemainingNeverNegative() {
        let tracker = UsageTracker()
        for _ in 0..<(AppConstants.freeChatMessagesPerMonth + 10) {
            tracker.recordChatMessage(inputTokens: 1, outputTokens: 1)
        }
        XCTAssertEqual(tracker.remainingChatMessages, 0)
    }

    // MARK: - Reset Logic

    func testResetOnNewMonth() {
        let tracker = UsageTracker()
        tracker.recordChatMessage(inputTokens: 100, outputTokens: 50)
        XCTAssertEqual(tracker.chatMessagesThisMonth, 1)

        // Simulate a different month
        tracker.monthKey = "2020-01"
        tracker.resetIfNeeded()
        XCTAssertEqual(tracker.chatMessagesThisMonth, 0)
    }

    func testResetOnNewWeek() {
        let tracker = UsageTracker()
        tracker.recordCheckIn()
        XCTAssertEqual(tracker.checkInsThisWeek, 1)

        // Simulate a different week
        tracker.weekKey = "2020-W01"
        tracker.resetIfNeeded()
        XCTAssertEqual(tracker.checkInsThisWeek, 0)
    }

    func testNoResetWithinSamePeriod() {
        let tracker = UsageTracker()
        tracker.recordChatMessage(inputTokens: 100, outputTokens: 50)
        tracker.recordCheckIn()

        tracker.resetIfNeeded()
        // Should not have reset since we're in the same month/week
        XCTAssertEqual(tracker.chatMessagesThisMonth, 1)
        XCTAssertEqual(tracker.checkInsThisWeek, 1)
    }

    // MARK: - Integrity

    func testIntegrityHashUpdatedOnRecord() {
        let tracker = UsageTracker()
        XCTAssertEqual(tracker.integrityHash, "")

        tracker.recordChatMessage(inputTokens: 10, outputTokens: 5)
        XCTAssertFalse(tracker.integrityHash.isEmpty)
    }

    func testIntegrityVerificationPasses() {
        let tracker = UsageTracker()
        tracker.recordChatMessage(inputTokens: 10, outputTokens: 5)
        XCTAssertTrue(tracker.verifyIntegrity())
    }

    func testIntegrityVerificationFailsOnTampering() {
        let tracker = UsageTracker()
        tracker.recordChatMessage(inputTokens: 10, outputTokens: 5)
        let originalHash = tracker.integrityHash

        // Tamper with the counter
        tracker.chatMessagesThisMonth = 0
        XCTAssertFalse(tracker.verifyIntegrity())

        // Restore counter but hash won't match the recomputation
        // because the tamperer doesn't have the key
        tracker.chatMessagesThisMonth = 1
        // Should still verify since we restored the correct value
        XCTAssertEqual(tracker.integrityHash, originalHash)
        XCTAssertTrue(tracker.verifyIntegrity())
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() throws {
        let tracker = UsageTracker()
        tracker.recordChatMessage(inputTokens: 100, outputTokens: 50)
        tracker.recordCheckIn()
        context.insert(tracker)
        try context.save()

        let descriptor = FetchDescriptor<UsageTracker>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.chatMessagesThisMonth, 1)
        XCTAssertEqual(fetched.first?.checkInsThisWeek, 1)
    }
}
