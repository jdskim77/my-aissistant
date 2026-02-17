import Foundation
@testable import MyAIssistant

final class MockAIProvider: AIProvider, @unchecked Sendable {
    var responseToReturn: AIResponse = AIResponse(content: "Mock response", inputTokens: 10, outputTokens: 20)
    var errorToThrow: Error?
    var sendMessageCallCount = 0
    var lastUserMessage: String?
    var lastSystemPrompt: String?

    func sendMessage(
        userMessage: String,
        conversationHistory: [ChatMessage],
        systemPrompt: String
    ) async throws -> AIResponse {
        sendMessageCallCount += 1
        lastUserMessage = userMessage
        lastSystemPrompt = systemPrompt
        if let error = errorToThrow {
            throw error
        }
        return responseToReturn
    }
}
