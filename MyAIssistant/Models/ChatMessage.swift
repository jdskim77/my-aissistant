import Foundation
import SwiftData

enum MessageRole: String, Codable {
    case user
    case assistant
}

@Model
final class ChatMessage {
    var id: String = UUID().uuidString
    var roleRaw: String = "assistant"
    var content: String = ""
    var timestamp: Date = Date()
    var conversationID: String = "main"

    /// True when this message is an app-generated error stub (e.g. "I'm not
    /// connected…"). Shown inline to the user for continuity, but excluded
    /// from the history sent back to the AI so it never treats its own
    /// app-generated apology as a prior assistant turn.
    var isErrorStub: Bool = false

    /// True when this message is the hardcoded `SafeResourceCopy.message()`
    /// emitted by the crisis gate (in either ChatManager.send or
    /// DailyRecapGenerator.generate). Drives a distinct ChatBubble
    /// rendering — coral framing, "Support resources" header, tappable
    /// hotline link — so screen-reader users hear safety framing instead
    /// of the standard "Message from assistant" announcement, and so the
    /// hotline URL is interactable instead of plain text. Persisted with
    /// a default of false so existing rows decode lightweight
    /// (per SchemaVersioning.swift's single-baseline policy).
    var isSafetyResource: Bool = false

    @Transient
    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }

    /// Whether this message should be included in the conversation
    /// history sent to the LLM on subsequent sends. False for:
    ///   - `isErrorStub` (app-generated connectivity stubs the model
    ///     never said).
    ///   - `isSafetyResource` (BOTH the user's crisis-flagged input
    ///     and the assistant safety reply — sending either to the
    ///     model leaks crisis content into a future prompt and primes
    ///     the model to imitate the safety framing).
    /// Centralized here so the rule lives next to the flags rather
    /// than duplicated in every history filter at the call site —
    /// keeps the safety contract from drifting silently.
    @Transient
    var shouldSendToAI: Bool {
        !isErrorStub && !isSafetyResource
    }

    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        conversationID: String = "main",
        isErrorStub: Bool = false,
        isSafetyResource: Bool = false
    ) {
        self.id = id
        self.roleRaw = role.rawValue
        self.content = content
        self.timestamp = timestamp
        self.conversationID = conversationID
        self.isErrorStub = isErrorStub
        self.isSafetyResource = isSafetyResource
    }
}
