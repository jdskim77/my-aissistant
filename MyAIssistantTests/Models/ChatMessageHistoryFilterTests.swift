import XCTest
@testable import MyAIssistant

/// Regression tests for the `ChatMessage.shouldSendToAI` property —
/// the single source of truth for what gets included in conversation
/// history sent to the LLM. Two CRITICAL safety bugs (BUG-01/BUG-02 from
/// the chat-bubble QA pass) were rooted in `cleanHistory.filter { !$0.isErrorStub }`
/// missing the `isSafetyResource` exclusion, causing crisis content
/// (both the user's input and the safety reply) to leak into subsequent
/// LLM calls.
///
/// These tests pin the filter's truth table so any future flag-set
/// regression will fail loudly here instead of silently leaking PII /
/// crisis text to Anthropic.
final class ChatMessageHistoryFilterTests: XCTestCase {

    // MARK: - Truth table

    func test_shouldSendToAI_normalUserMessage_isTrue() {
        let m = ChatMessage(role: .user, content: "Hello")
        XCTAssertTrue(m.shouldSendToAI)
    }

    func test_shouldSendToAI_normalAssistantMessage_isTrue() {
        let m = ChatMessage(role: .assistant, content: "Hi there")
        XCTAssertTrue(m.shouldSendToAI)
    }

    func test_shouldSendToAI_errorStub_isFalse() {
        let m = ChatMessage(
            role: .assistant,
            content: "I'm not connected right now",
            isErrorStub: true
        )
        XCTAssertFalse(m.shouldSendToAI)
    }

    func test_shouldSendToAI_safetyResourceAssistant_isFalse() {
        // The assistant safety reply must never be replayed to the LLM
        // as a prior turn. Echoing the SafeResourceCopy text would
        // leak crisis content into the prompt and prime the model
        // to imitate the safety framing.
        let m = ChatMessage(
            role: .assistant,
            content: "If you're going through something heavy...",
            isSafetyResource: true
        )
        XCTAssertFalse(m.shouldSendToAI)
    }

    func test_shouldSendToAI_safetyResourceUser_isFalse() {
        // The user's crisis-flagged input is also marked
        // `isSafetyResource` so it gets the same exclusion.
        // Without this, the original crisis text the user typed
        // would be sent to the LLM as conversation history on
        // every subsequent (non-crisis) message — defeating the
        // gate's purpose entirely. CRITICAL safety regression
        // gate.
        let m = ChatMessage(
            role: .user,
            content: "I want to die",
            isSafetyResource: true
        )
        XCTAssertFalse(m.shouldSendToAI)
    }

    func test_shouldSendToAI_bothFlagsSet_isFalse() {
        let m = ChatMessage(
            role: .assistant,
            content: "...",
            isErrorStub: true,
            isSafetyResource: true
        )
        XCTAssertFalse(m.shouldSendToAI)
    }

    // MARK: - Filter behavior on a typical history slice

    func test_filter_excludesAllStubsAndSafetyMessages() {
        let history: [ChatMessage] = [
            ChatMessage(role: .user, content: "Hi"),
            ChatMessage(role: .assistant, content: "Hello"),
            // Safety route: BOTH flagged
            ChatMessage(role: .user, content: "I want to die", isSafetyResource: true),
            ChatMessage(role: .assistant, content: "Support resources...", isSafetyResource: true),
            // Error stub
            ChatMessage(role: .assistant, content: "I'm not connected", isErrorStub: true),
            // Normal continuation
            ChatMessage(role: .user, content: "What's on my plate today?"),
        ]

        let filtered = history.filter(\.shouldSendToAI)

        XCTAssertEqual(filtered.count, 3,
                       "Expect 3 normal messages to survive — 2 safety-flagged + 1 error-stub must be dropped.")
        XCTAssertEqual(filtered.map(\.content), [
            "Hi",
            "Hello",
            "What's on my plate today?",
        ])
    }

    /// Critical: a future contributor must not be able to "fix" the
    /// filter back to `!$0.isErrorStub` without this test screaming.
    /// Pin the contract by asserting the safety reply text is NEVER
    /// in the post-filter slice.
    func test_filter_neverLeaksSafetyResourceBody() {
        let safety = ChatMessage(
            role: .assistant,
            content: "If you're going through something heavy...",
            isSafetyResource: true
        )
        let crisis = ChatMessage(
            role: .user,
            content: "I want to die",
            isSafetyResource: true
        )
        let normal = ChatMessage(role: .user, content: "Normal turn")

        let history = [normal, crisis, safety]
        let filtered = history.filter(\.shouldSendToAI)
        let bodies = filtered.map(\.content)

        XCTAssertFalse(bodies.contains(safety.content),
                       "Safety reply body must never appear in LLM-bound history.")
        XCTAssertFalse(bodies.contains(crisis.content),
                       "User's crisis input must never appear in LLM-bound history.")
    }
}
