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
    // NOTE: Per-week check-in gating was removed — free tier now only meters chat
    // messages per month. These tests are intentionally omitted.

    // MARK: - Usage Tracking

    func testRecordChatMessageIncrementsCount() {
        XCTAssertEqual(sut.chatUsedThisMonth, 0)
        sut.recordChatMessage(inputTokens: 100, outputTokens: 50)
        XCTAssertEqual(sut.chatUsedThisMonth, 1)
    }

    func testRemainingChatMessages() {
        XCTAssertEqual(sut.remainingChatMessages, AppConstants.freeChatMessagesPerMonth)
        sut.recordChatMessage(inputTokens: 100, outputTokens: 50)
        XCTAssertEqual(sut.remainingChatMessages, AppConstants.freeChatMessagesPerMonth - 1)
    }

    func testRemainingNeverNegative() {
        for _ in 0..<(AppConstants.freeChatMessagesPerMonth + 5) {
            sut.recordChatMessage(inputTokens: 10, outputTokens: 5)
        }
        XCTAssertEqual(sut.remainingChatMessages, 0)
    }
}
