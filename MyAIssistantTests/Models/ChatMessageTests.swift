import XCTest
import SwiftData
@testable import MyAIssistant

@MainActor
final class ChatMessageTests: XCTestCase {

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

    func testUserMessageInit() {
        let msg = ChatMessage(role: .user, content: "Hello there")
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.roleRaw, "user")
        XCTAssertEqual(msg.content, "Hello there")
        XCTAssertEqual(msg.conversationID, "main")
        XCTAssertFalse(msg.id.isEmpty)
    }

    func testAssistantMessageInit() {
        let msg = ChatMessage(role: .assistant, content: "Hi!")
        XCTAssertEqual(msg.role, .assistant)
        XCTAssertEqual(msg.roleRaw, "assistant")
    }

    func testCustomConversationID() {
        let msg = ChatMessage(role: .user, content: "test", conversationID: "conv-123")
        XCTAssertEqual(msg.conversationID, "conv-123")
    }

    // MARK: - Role Computed Property

    func testRoleSetterUpdatesRaw() {
        let msg = ChatMessage(role: .user, content: "test")
        msg.role = .assistant
        XCTAssertEqual(msg.roleRaw, "assistant")
    }

    func testInvalidRoleFallsBackToAssistant() {
        let msg = ChatMessage(role: .user, content: "test")
        msg.roleRaw = "invalid"
        XCTAssertEqual(msg.role, .assistant)
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() throws {
        let msg = ChatMessage(role: .user, content: "Persisted message", conversationID: "test-conv")
        context.insert(msg)
        try context.save()

        let descriptor = FetchDescriptor<ChatMessage>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.content, "Persisted message")
        XCTAssertEqual(fetched.first?.conversationID, "test-conv")
    }

    func testMultipleMessagesInConversation() throws {
        let msg1 = ChatMessage(role: .user, content: "Question", conversationID: "conv1")
        let msg2 = ChatMessage(role: .assistant, content: "Answer", conversationID: "conv1")
        let msg3 = ChatMessage(role: .user, content: "Other", conversationID: "conv2")

        context.insert(msg1)
        context.insert(msg2)
        context.insert(msg3)
        try context.save()

        let descriptor = FetchDescriptor<ChatMessage>()
        let all = try context.fetch(descriptor)
        XCTAssertEqual(all.count, 3)

        let conv1 = all.filter { $0.conversationID == "conv1" }
        XCTAssertEqual(conv1.count, 2)
    }
}
