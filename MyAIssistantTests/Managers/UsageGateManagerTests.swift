import XCTest
import SwiftData
@testable import MyAIssistant

@MainActor
final class UsageGateManagerTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var sut: UsageGateManager!

    override func setUp() async throws {
        container = try TestModelContainer.create()
        context = container.mainContext
        sut = UsageGateManager(modelContext: context)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        sut = nil
    }

    // MARK: - Chat Gating

    func testFreeTierCanSendChatInitially() {
        XCTAssertTrue(sut.canSendChat(tier: .free))
    }

    func testFreeTierBlockedAfterLimit() {
        // Exhaust free chat limit
        for _ in 0..<AppConstants.freeChatMessagesPerMonth {
            sut.recordChatMessage(inputTokens: 100, outputTokens: 50)
        }
        XCTAssertFalse(sut.canSendChat(tier: .free))
    }

    func testProTierAlwaysCanChat() {
        // Exhaust way beyond free limit
        for _ in 0..<50 {
            sut.recordChatMessage(inputTokens: 100, outputTokens: 50)
        }
        XCTAssertTrue(sut.canSendChat(tier: .pro))
    }

    func testStudentTierAlwaysCanChat() {
        for _ in 0..<50 {
            sut.recordChatMessage(inputTokens: 100, outputTokens: 50)
        }
        XCTAssertTrue(sut.canSendChat(tier: .student))
    }

    func testPowerUserTierAlwaysCanChat() {
        for _ in 0..<50 {
            sut.recordChatMessage(inputTokens: 100, outputTokens: 50)
        }
        XCTAssertTrue(sut.canSendChat(tier: .powerUser))
    }

    // MARK: - Check-in Gating

    func testFreeTierCanDoCheckInInitially() {
        XCTAssertTrue(sut.canDoCheckIn(tier: .free))
    }

    func testFreeTierBlockedAfterCheckInLimit() {
        for _ in 0..<AppConstants.freeCheckInsPerWeek {
            sut.recordCheckIn()
        }
        XCTAssertFalse(sut.canDoCheckIn(tier: .free))
    }

    func testProTierAlwaysCanCheckIn() {
        for _ in 0..<20 {
            sut.recordCheckIn()
        }
        XCTAssertTrue(sut.canDoCheckIn(tier: .pro))
    }

    // MARK: - Usage Tracking

    func testRecordChatMessageIncrementsCount() {
        XCTAssertEqual(sut.chatUsedThisMonth, 0)
        sut.recordChatMessage(inputTokens: 100, outputTokens: 50)
        XCTAssertEqual(sut.chatUsedThisMonth, 1)
    }

    func testRecordCheckInIncrementsCount() {
        XCTAssertEqual(sut.checkInsUsedThisWeek, 0)
        sut.recordCheckIn()
        XCTAssertEqual(sut.checkInsUsedThisWeek, 1)
    }

    func testRemainingChatMessages() {
        XCTAssertEqual(sut.remainingChatMessages, AppConstants.freeChatMessagesPerMonth)
        sut.recordChatMessage(inputTokens: 100, outputTokens: 50)
        XCTAssertEqual(sut.remainingChatMessages, AppConstants.freeChatMessagesPerMonth - 1)
    }

    func testRemainingCheckIns() {
        XCTAssertEqual(sut.remainingCheckIns, AppConstants.freeCheckInsPerWeek)
        sut.recordCheckIn()
        XCTAssertEqual(sut.remainingCheckIns, AppConstants.freeCheckInsPerWeek - 1)
    }

    func testRemainingNeverNegative() {
        for _ in 0..<(AppConstants.freeChatMessagesPerMonth + 5) {
            sut.recordChatMessage(inputTokens: 10, outputTokens: 5)
        }
        XCTAssertEqual(sut.remainingChatMessages, 0)
    }
}
