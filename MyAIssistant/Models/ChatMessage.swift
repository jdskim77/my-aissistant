import Foundation
import SwiftData

enum MessageRole: String, Codable {
    case user
    case assistant
}

@Model
final class ChatMessage {
    var id: String
    var roleRaw: String
    var content: String
    var timestamp: Date
    var conversationID: String

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
        conversationID: String = "main"
    ) {
        self.id = id
        self.roleRaw = role.rawValue
        self.content = content
        self.timestamp = timestamp
        self.conversationID = conversationID
    }
}
