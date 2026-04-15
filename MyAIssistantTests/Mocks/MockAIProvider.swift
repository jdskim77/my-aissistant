import Foundation
@testable import MyAIssistant

final class MockAIProvider: AIProvider, @unchecked Sendable {
    var responseToReturn: AIResponse = AIResponse(content: "Mock response", inputTokens: 10, outputTokens: 20)
    var errorToThrow: Error?
    var sendMessageCallCount = 0
    var sendVisionMessageCallCount = 0
    var lastUserMessage: String?
    var lastSystemPrompt: String?
    var lastVisionPrompt: String?

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

    func sendVisionMessage(
        prompt: String,
        imageData: Data,
        mediaType: String
    ) async throws -> AIResponse {
        sendVisionMessageCallCount += 1
        lastVisionPrompt = prompt
        if let error = errorToThrow {
            throw error
        }
        return responseToReturn
    }
}
