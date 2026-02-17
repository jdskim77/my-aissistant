import Foundation

actor OpenAIProvider: AIProvider {
    private let apiKey: String
    private let model: String
    private let client: APIClient
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(apiKey: String, model: String = "gpt-4o") {
        self.apiKey = apiKey
        self.model = model
        self.client = APIClient()
    }

    func sendMessage(
        userMessage: String,
        conversationHistory: [ChatMessage],
        systemPrompt: String
    ) async throws -> AIResponse {
        let messages = buildMessages(
            conversationHistory: conversationHistory,
            userMessage: userMessage,
            systemPrompt: systemPrompt
        )

        let body: [String: Any] = [
            "model": model,
            "max_tokens": AppConstants.defaultMaxTokens,
            "messages": messages
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        let headers: [String: String] = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(apiKey)"
        ]

        let response = try await client.post(url: endpoint, headers: headers, body: jsonData)

        if response.statusCode == 429 {
            throw AIError.rateLimited
        }

        guard response.statusCode == 200 else {
            let errorBody = String(data: response.data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError(statusCode: response.statusCode, message: errorBody)
        }

        return try parseResponse(response.data)
    }

    // MARK: - Request Building

    private func buildMessages(
        conversationHistory: [ChatMessage],
        userMessage: String,
        systemPrompt: String
    ) -> [[String: String]] {
        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        for msg in conversationHistory.suffix(10) {
            messages.append([
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.content
            ])
        }
        messages.append(["role": "user", "content": userMessage])
        return messages
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> AIResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.parsingError
        }

        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["prompt_tokens"] as? Int ?? 0
        let outputTokens = usage?["completion_tokens"] as? Int ?? 0

        return AIResponse(
            content: content,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
}
