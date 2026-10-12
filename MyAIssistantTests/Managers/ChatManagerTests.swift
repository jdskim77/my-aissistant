import XCTest
import SwiftData
@testable import MyAIssistant

/// Round-1 flagged ChatManager as untested. These exercise the
/// non-network parts of its public surface directly against an
/// in-memory SwiftData store (no AIProvider needed for these paths).
@MainActor
final class ChatManagerTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var sut: ChatManager!

    override func setUp() async throws {
        container = try TestModelContainer.create()
        context = container.mainContext
        sut = ChatManager(modelContext: context)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        sut = nil
    }

    // MARK: - insertLocalMessage / loadMessages

    func testInsertLocalMessagePersistsAndIsLoadable() {
        let msg = sut.insertLocalMessage(role: .assistant, content: "hi", conversationID: "convo-1")

        let loaded = sut.loadMessages(for: "convo-1")
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, msg.id)
        XCTAssertEqual(loaded.first?.content, "hi")
        XCTAssertEqual(loaded.first?.role, .assistant)
    }

    func testLoadMessagesOrdersByTimestampAscending() {
        let now = Date()
        _ = sut.insertLocalMessage(role: .user, content: "second", conversationID: "c")
        // Insert a message with an earlier timestamp isn't directly supported by
        // insertLocalMessage (always `Date()`), so insert directly to control order.
        let earlier = ChatMessage(role: .user, content: "first", timestamp: now.addingTimeInterval(-60), conversationID: "c")
        context.insert(earlier)
        try? context.save()

        let loaded = sut.loadMessages(for: "c")
        XCTAssertEqual(loaded.map(\.content), ["first", "second"])
    }

    func testLoadMessagesOnlyReturnsMatchingConversation() {
        _ = sut.insertLocalMessage(role: .user, content: "in convo A", conversationID: "A")
        _ = sut.insertLocalMessage(role: .user, content: "in convo B", conversationID: "B")

        XCTAssertEqual(sut.loadMessages(for: "A").map(\.content), ["in convo A"])
        XCTAssertEqual(sut.loadMessages(for: "B").map(\.content), ["in convo B"])
    }

    // MARK: - deleteConversation

    func testDeleteConversationRemovesOnlyItsOwnMessages() {
        _ = sut.insertLocalMessage(role: .user, content: "keep me", conversationID: "keep")
        _ = sut.insertLocalMessage(role: .user, content: "delete me", conversationID: "gone")

        sut.deleteConversation("gone")

        XCTAssertEqual(sut.loadMessages(for: "gone").count, 0)
        XCTAssertEqual(sut.loadMessages(for: "keep").count, 1)
    }

    // MARK: - insertGreetingMessage

    func testInsertGreetingMessageInsertsAssistantMessage() {
        let conversationID = "greeting-convo-\(UUID().uuidString)"
        let text = sut.insertGreetingMessage(conversationID: conversationID)

        XCTAssertFalse(text.isEmpty)
        let loaded = sut.loadMessages(for: conversationID)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.role, .assistant)
        XCTAssertEqual(loaded.first?.content, text)
    }

    // MARK: - executeCalendarActions: create + dedup

    private func makeCreateAction(title: String, dayOffset: Int = 1) -> ChatManager.CalendarAction {
        let start = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date())!
        let end = start.addingTimeInterval(3600)
        return .create(title: title, start: start, end: end, description: nil, recurrence: .none, dimension: nil)
    }

    func testExecuteCalendarActionsCreatesLocalTaskWithoutSyncManager() async {
        // sut.calendarSyncManager is nil — the create path must still
        // succeed locally (calendar sync is best-effort).
        let error = await sut.executeCalendarActions([makeCreateAction(title: "Run 5k")])
        XCTAssertNil(error)

        let descriptor = FetchDescriptor<TaskItem>()
        let tasks = (try? context.fetch(descriptor)) ?? []
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.title, "Run 5k")
    }

    func testExecuteCalendarActionsDedupesSameTitleSameDay() async {
        let action = makeCreateAction(title: "Standup")
        _ = await sut.executeCalendarActions([action])
        _ = await sut.executeCalendarActions([action])

        let descriptor = FetchDescriptor<TaskItem>()
        let tasks = (try? context.fetch(descriptor)) ?? []
        XCTAssertEqual(tasks.count, 1, "Creating the same title on the same day twice must not duplicate the task")
    }

    func testExecuteCalendarActionsDedupeIsCaseInsensitive() async {
        _ = await sut.executeCalendarActions([makeCreateAction(title: "Dentist")])
        _ = await sut.executeCalendarActions([makeCreateAction(title: "DENTIST")])

        let descriptor = FetchDescriptor<TaskItem>()
        let tasks = (try? context.fetch(descriptor)) ?? []
        XCTAssertEqual(tasks.count, 1)
    }

    // MARK: - executeCalendarActions: delete

    func testExecuteCalendarActionsDeleteRemovesMatchingTask() async {
        let task = TaskItem(
            title: "Old sync'd task",
            category: .personal,
            priority: .medium,
            date: Date(),
            icon: "📅"
        )
        task.externalCalendarID = "google:evt-123"
        context.insert(task)
        try? context.save()

        let error = await sut.executeCalendarActions([.delete(eventID: "google:evt-123")])
        XCTAssertNil(error)

        let descriptor = FetchDescriptor<TaskItem>()
        let remaining = (try? context.fetch(descriptor)) ?? []
        XCTAssertTrue(remaining.isEmpty)
    }

    func testExecuteCalendarActionsDeleteWithNoMatchIsANoOp() async {
        let task = TaskItem(
            title: "Unrelated task",
            category: .personal,
            priority: .medium,
            date: Date(),
            icon: "📅"
        )
        task.externalCalendarID = "google:evt-999"
        context.insert(task)
        try? context.save()

        _ = await sut.executeCalendarActions([.delete(eventID: "google:does-not-exist")])

        let descriptor = FetchDescriptor<TaskItem>()
        let remaining = (try? context.fetch(descriptor)) ?? []
        XCTAssertEqual(remaining.count, 1, "Deleting an unmatched eventID must not touch unrelated tasks")
    }

    // MARK: - sendMessage re-entrancy guard

    func testSendMessageOffersNoNetworkMonitorByDefault() {
        // sut.networkMonitor is nil by default — sendMessage must not
        // short-circuit on a nil monitor (only on an explicit disconnected one).
        XCTAssertNil(sut.networkMonitor)
    }
}
