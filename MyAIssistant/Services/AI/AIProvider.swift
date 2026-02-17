import Foundation

// MARK: - AI Response

struct AIResponse {
    let content: String
    let inputTokens: Int
    let outputTokens: Int
}

// MARK: - AI Provider Protocol

protocol AIProvider: Sendable {
    func sendMessage(
        userMessage: String,
        conversationHistory: [ChatMessage],
        systemPrompt: String
    ) async throws -> AIResponse
}

// MARK: - AI Errors

enum AIError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parsingError
    case noAPIKey
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
        case .rateLimited:
            return "Rate limited — please try again shortly"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
