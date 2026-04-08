import Foundation

/// Client for the Thrivn backend proxy (Cloudflare Worker).
/// Handles Sign in with Apple, JWT lifecycle, and authenticated AI chat.
///
/// The backend URL is configured via `AppConstants.thrivnBackendURL`.
/// Tokens are stored in the Keychain and refreshed automatically on 401.
actor ThrivnBackendService: AIProvider {

    // MARK: - Configuration

    private let baseURL: URL
    private let model: String
    private let session: URLSession
    private let keychain: KeychainService

    /// Anthropic-compatible message structure used in /v1/chat payloads
    private struct ChatRequestMessage: Encodable {
        let role: String
        let content: String
    }

    init(model: String = AppConstants.haikuModel, keychain: KeychainService) {
        self.baseURL = URL(string: AppConstants.thrivnBackendURL)!
        self.model = model
        self.keychain = keychain
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - AIProvider conformance

    func sendMessage(
        userMessage: String,
        conversationHistory: [ChatMessage],
        systemPrompt: String
    ) async throws -> AIResponse {
        let messages = buildMessages(history: conversationHistory, userMessage: userMessage)
        return try await postChat(systemPrompt: systemPrompt, messages: messages)
    }

    func sendVisionMessage(
        prompt: String,
        imageData: Data,
        mediaType: String
    ) async throws -> AIResponse {
        // Vision is not yet supported through the proxy. Fall back to a stub error
        // until the /v1/chat endpoint adds image support.
        _ = (prompt, imageData, mediaType)
        throw AIError.apiError(statusCode: 501, message: "Vision messages not yet supported via the Thrivn backend")
    }

    // MARK: - Authentication

    /// Sign in with Apple — exchanges the Apple identity token for Thrivn JWT + refresh token.
    /// Stores both in the Keychain on success.
    func signInWithApple(
        identityToken: String,
        fullName: String?,
        email: String?
    ) async throws -> ThrivnUser {
        struct Body: Encodable {
            let identity_token: String
            let full_name: String?
            let email: String?
        }
        let body = Body(identity_token: identityToken, full_name: fullName, email: email)

        let url = baseURL.appendingPathComponent("v1/auth/apple")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let envelope = try JSONDecoder().decode(AuthEnvelope.self, from: data)
        keychain.save(key: AppConstants.thrivnAccessTokenKey, value: envelope.data.access_token)
        keychain.save(key: AppConstants.thrivnRefreshTokenKey, value: envelope.data.refresh_token)
        return envelope.data.user
    }

    /// Refresh the access token using the stored refresh token. Throws if no refresh token exists.
    func refreshTokens() async throws {
        guard let refreshToken = keychain.read(key: AppConstants.thrivnRefreshTokenKey),
              !refreshToken.isEmpty else {
            throw AIError.noAPIKey
        }

        struct Body: Encodable { let refresh_token: String }
        let url = baseURL.appendingPathComponent("v1/auth/refresh")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(refresh_token: refreshToken))

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let envelope = try JSONDecoder().decode(RefreshEnvelope.self, from: data)
        keychain.save(key: AppConstants.thrivnAccessTokenKey, value: envelope.data.access_token)
        keychain.save(key: AppConstants.thrivnRefreshTokenKey, value: envelope.data.refresh_token)
    }

    /// Logout: revoke refresh token server-side and clear stored credentials.
    func signOut() async {
        if let refreshToken = keychain.read(key: AppConstants.thrivnRefreshTokenKey),
           !refreshToken.isEmpty {
            struct Body: Encodable { let refresh_token: String }
            let url = baseURL.appendingPathComponent("v1/auth/logout")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(Body(refresh_token: refreshToken))
            _ = try? await session.data(for: request)
        }
        keychain.delete(key: AppConstants.thrivnAccessTokenKey)
        keychain.delete(key: AppConstants.thrivnRefreshTokenKey)
    }

    /// Returns true if a refresh token is stored.
    func isSignedIn() -> Bool {
        let refresh = keychain.read(key: AppConstants.thrivnRefreshTokenKey) ?? ""
        return !refresh.isEmpty
    }

    // MARK: - Usage stats

    func fetchUsage() async throws -> ThrivnUsage {
        let url = baseURL.appendingPathComponent("v1/usage")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
        return try JSONDecoder().decode(UsageEnvelope.self, from: data).data
    }

    // MARK: - Chat (private)

    private func postChat(systemPrompt: String, messages: [ChatRequestMessage]) async throws -> AIResponse {
        struct Body: Encodable {
            let model: String
            let max_tokens: Int
            let messages: [ChatRequestMessage]
            let system: String
            let stream: Bool
        }
        let body = Body(
            model: model,
            max_tokens: 1024,
            messages: messages,
            system: systemPrompt,
            stream: false
        )

        let url = baseURL.appendingPathComponent("v1/chat")

        // Try once, refresh on 401, retry once
        do {
            return try await performChatRequest(url: url, body: body)
        } catch AIError.apiError(statusCode: 401, _) {
            try await refreshTokens()
            return try await performChatRequest(url: url, body: body)
        }
    }

    private func performChatRequest<B: Encodable>(url: URL, body: B) async throws -> AIResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        // Backend returns the raw Anthropic response when stream=false.
        // Decode the standard Anthropic response format.
        return try parseAnthropicResponse(data)
    }

    private func accessToken() async throws -> String {
        guard let token = keychain.read(key: AppConstants.thrivnAccessTokenKey),
              !token.isEmpty else {
            throw AIError.noAPIKey
        }
        return token
    }

    // MARK: - Helpers

    private func buildMessages(history: [ChatMessage], userMessage: String) -> [ChatRequestMessage] {
        var messages: [ChatRequestMessage] = []
        // Last 10 messages from history (matches existing AnthropicProvider behavior)
        let recent = history.suffix(10)
        for message in recent {
            let role = (message.role == .user) ? "user" : "assistant"
            messages.append(ChatRequestMessage(role: role, content: message.content))
        }
        messages.append(ChatRequestMessage(role: "user", content: userMessage))
        return messages
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw AIError.apiError(statusCode: 401, message: "Authentication required")
        case 429:
            throw AIError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError(statusCode: http.statusCode, message: body)
        }
    }

    private func parseAnthropicResponse(_ data: Data) throws -> AIResponse {
        struct AnthropicContent: Decodable {
            let type: String
            let text: String?
        }
        struct AnthropicUsage: Decodable {
            let input_tokens: Int
            let output_tokens: Int
        }
        struct AnthropicMessage: Decodable {
            let content: [AnthropicContent]
            let usage: AnthropicUsage
        }

        let message = try JSONDecoder().decode(AnthropicMessage.self, from: data)
        let text = message.content.compactMap { $0.text }.joined(separator: "\n")
        return AIResponse(
            content: text,
            inputTokens: message.usage.input_tokens,
            outputTokens: message.usage.output_tokens
        )
    }

    // MARK: - Decoding envelopes

    struct ThrivnUser: Decodable {
        let id: String
        let display_name: String?
        let tier: String
    }

    struct ThrivnUsage: Decodable {
        let tier: String
        let monthly_used: Int
        let monthly_limit: Int?
        let monthly_remaining: Int?
        let per_minute_limit: Int
        let max_tokens_per_request: Int
        let allowed_models: [String]
    }

    private struct AuthEnvelope: Decodable {
        struct Data: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Int
            let user: ThrivnUser
        }
        let data: Data
    }

    private struct RefreshEnvelope: Decodable {
        struct Data: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Int
        }
        let data: Data
    }

    private struct UsageEnvelope: Decodable {
        let data: ThrivnUsage
    }
}
