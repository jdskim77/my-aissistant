import Foundation

// MARK: - AI Response

struct AIResponse {
    let content: String
    let inputTokens: Int
    let outputTokens: Int
    /// Tokens written into the prompt cache on this request (Anthropic only).
    /// `nil` for providers that don't support caching.
    let cacheCreationInputTokens: Int?
    /// Tokens served from the prompt cache on this request (Anthropic only).
    /// `nil` for providers that don't support caching.
    let cacheReadInputTokens: Int?

    init(
        content: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationInputTokens: Int? = nil,
        cacheReadInputTokens: Int? = nil
    ) {
        self.content = content
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }
}

// MARK: - AI Provider Protocol

protocol AIProvider: Sendable {
    func sendMessage(
        userMessage: String,
        conversationHistory: [ChatMessage],
        systemPrompt: String
    ) async throws -> AIResponse

    /// Send a message with a system prompt split into a stable (cacheable) block and a
    /// volatile block that changes per request. Providers that support prompt caching
    /// (Anthropic) cache the stable block; others concatenate and fall through.
    func sendMessage(
        userMessage: String,
        conversationHistory: [ChatMessage],
        systemPromptStable: String,
        systemPromptVolatile: String
    ) async throws -> AIResponse

    /// Send a message with an image attachment (vision).
    func sendVisionMessage(
        prompt: String,
        imageData: Data,
        mediaType: String
    ) async throws -> AIResponse
}

extension AIProvider {
    /// Default implementation: concatenate stable + volatile and route through the
    /// single-string sendMessage. Providers with native caching support should override.
    func sendMessage(
        userMessage: String,
        conversationHistory: [ChatMessage],
        systemPromptStable: String,
        systemPromptVolatile: String
    ) async throws -> AIResponse {
        let combined: String
        if systemPromptVolatile.isEmpty {
            combined = systemPromptStable
        } else if systemPromptStable.isEmpty {
            combined = systemPromptVolatile
        } else {
            combined = systemPromptStable + "\n\n" + systemPromptVolatile
        }
        return try await sendMessage(
            userMessage: userMessage,
            conversationHistory: conversationHistory,
            systemPrompt: combined
        )
    }
}

// MARK: - AI Errors

enum AIError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parsingError
    case noAPIKey
    case sessionExpired
    case rateLimited
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from AI service"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .parsingError:
            return "Failed to parse AI response"
        case .noAPIKey:
            return "No API key configured"
        case .sessionExpired:
            return "Your session has expired — please sign in again"
        case .rateLimited:
            return "Rate limited — please try again shortly"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
