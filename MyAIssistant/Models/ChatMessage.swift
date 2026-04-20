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

    @Transient
    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        conversationID: String = "main",
        isErrorStub: Bool = false
    ) {
        self.id = id
        self.roleRaw = role.rawValue
        self.content = content
        self.timestamp = timestamp
        self.conversationID = conversationID
        self.isErrorStub = isErrorStub
    }
}
