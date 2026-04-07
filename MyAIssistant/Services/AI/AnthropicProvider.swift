import Foundation

actor AnthropicProvider: AIProvider {
    private let apiKey: String
    private let model: String
    private let client: APIClient
    private let endpoint: URL

    init(apiKey: String, model: String = AppConstants.sonnetModel) {
        self.apiKey = apiKey
        self.model = model
        self.client = APIClient()
        // Static URL from constants — safe to force-unwrap as it's compile-time known
        self.endpoint = URL(string: AppConstants.anthropicEndpoint)!
    }

    func sendMessage(
        userMessage: String,
        conversationHistory: [ChatMessage],
        systemPrompt: String
    ) async throws -> AIResponse {
        let messages = buildMessages(conversationHistory: conversationHistory, userMessage: userMessage)
        let body = buildRequestBody(systemPrompt: systemPrompt, messages: messages)

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        let headers: [String: String] = [
            "content-type": "application/json",
            "x-api-key": apiKey,
            "anthropic-version": AppConstants.anthropicAPIVersion
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

    func sendMessage(
        userMessage: String,
        conversationHistory: [ChatMessage],
        systemPromptStable: String,
        systemPromptVolatile: String
    ) async throws -> AIResponse {
        let messages = buildMessages(conversationHistory: conversationHistory, userMessage: userMessage)
        let body = buildSplitRequestBody(
            systemPromptStable: systemPromptStable,
            systemPromptVolatile: systemPromptVolatile,
            messages: messages
        )

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        let headers: [String: String] = [
            "content-type": "application/json",
            "x-api-key": apiKey,
            "anthropic-version": AppConstants.anthropicAPIVersion
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

    func sendVisionMessage(
        prompt: String,
        imageData: Data,
        mediaType: String
    ) async throws -> AIResponse {
        let base64 = imageData.base64EncodedString()

        let userContent: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": mediaType,
                    "data": base64
                ]
            ],
            [
                "type": "text",
                "text": prompt
            ]
        ]

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": userContent]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        let headers: [String: String] = [
            "content-type": "application/json",
            "x-api-key": apiKey,
            "anthropic-version": AppConstants.anthropicAPIVersion
        ]

        let response = try await client.post(url: endpoint, headers: headers, body: jsonData)

        guard response.statusCode == 200 else {
            let errorBody = String(data: response.data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError(statusCode: response.statusCode, message: errorBody)
        }

        return try parseResponse(response.data)
    }

    // MARK: - Request Building

    private func buildMessages(conversationHistory: [ChatMessage], userMessage: String) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        for msg in conversationHistory.suffix(10) {
            messages.append([
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.content
            ])
        }
        messages.append(["role": "user", "content": userMessage])
        return messages
    }

    private func buildRequestBody(systemPrompt: String, messages: [[String: Any]]) -> [String: Any] {
        // Single-block path: cache the entire prompt. Note that if the prompt includes
        // volatile content (today's schedule, stats), the cache will miss every call.
        // Prefer the split path (buildSplitRequestBody) for chat.
        let systemBlock: [[String: Any]] = [
            [
                "type": "text",
                "text": systemPrompt,
                "cache_control": ["type": "ephemeral"]
            ]
        ]

        return [
            "model": model,
            "max_tokens": AppConstants.defaultMaxTokens,
            "system": systemBlock,
            "messages": messages
        ]
    }

    private func buildSplitRequestBody(
        systemPromptStable: String,
        systemPromptVolatile: String,
        messages: [[String: Any]]
    ) -> [String: Any] {
        var systemBlocks: [[String: Any]] = []

        // Stable block: cached. Must be the FIRST block and meet Anthropic's
        // minimum cacheable size (~1024 tokens for Sonnet) for the cache to engage.
        if !systemPromptStable.isEmpty {
            systemBlocks.append([
                "type": "text",
                "text": systemPromptStable,
                "cache_control": ["type": "ephemeral"]
            ])
        }

        // Volatile block: not cached. Changes per request (date, schedule, stats).
        if !systemPromptVolatile.isEmpty {
            systemBlocks.append([
                "type": "text",
                "text": systemPromptVolatile
            ])
        }

        return [
            "model": model,
            "max_tokens": AppConstants.defaultMaxTokens,
            "system": systemBlocks,
            "messages": messages
        ]
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> AIResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw AIError.parsingError
        }

        // Extract token usage (including cache stats when available)
        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["input_tokens"] as? Int ?? 0
        let outputTokens = usage?["output_tokens"] as? Int ?? 0
        let cacheCreation = usage?["cache_creation_input_tokens"] as? Int
        let cacheRead = usage?["cache_read_input_tokens"] as? Int

        return AIResponse(
            content: text,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationInputTokens: cacheCreation,
            cacheReadInputTokens: cacheRead
        )
    }
}
