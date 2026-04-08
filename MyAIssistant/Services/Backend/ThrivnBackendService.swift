import Foundation

/// Client for the Thrivn backend proxy (Cloudflare Worker).
/// Handles Sign in with Apple, JWT lifecycle, and authenticated AI chat.
///
/// The backend URL is configured via `AppConstants.thrivnBackendURL`.
/// Tokens are stored in the Keychain (`whenUnlockedThisDeviceOnly`) and refreshed
/// automatically on 401. Concurrent refreshes are coalesced into a single network call.
actor ThrivnBackendService: AIProvider {

    // MARK: - Configuration

    private let baseURL: URL
    private let model: String
    private let session: URLSession
    private let keychain: KeychainService

    /// Coalesces concurrent refresh-token calls into a single network request.
    /// Without this, two parallel chat 401s would each call refreshTokens() and
    /// the first one's success would revoke the token the second one is using.
    private var inFlightRefresh: Task<Void, Error>?

    /// Static encoder/decoder reused across requests for performance.
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()
    private static let decoder: JSONDecoder = JSONDecoder()

    /// Anthropic-compatible message structure used in /v1/chat payloads
    private struct ChatRequestMessage: Encodable {
        let role: String
        let content: String
    }

    init(model: String = AppConstants.haikuModel, keychain: KeychainService) {
        // Fall back to a known-good URL if AppConstants is misconfigured at runtime.
        // Avoids the force-unwrap crash on app launch if the constant is ever changed.
        self.baseURL = URL(string: AppConstants.thrivnBackendURL)
            ?? URL(string: "https://thrivn-api.jdskim77.workers.dev")!
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
        request.httpBody = try Self.encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let envelope = try Self.decoder.decode(AuthEnvelope.self, from: data)
        try persistTokens(
            accessToken: envelope.data.access_token,
            refreshToken: envelope.data.refresh_token
        )
        return envelope.data.user
    }

    /// Refresh the access token using the stored refresh token.
    /// Coalesces concurrent calls — if a refresh is already in flight, waits for it
    /// instead of triggering a second one (which would race and revoke each other).
    func refreshTokens() async throws {
        // If a refresh is already running, await its result
        if let existing = inFlightRefresh {
            try await existing.value
            return
        }

        let task = Task<Void, Error> {
            try await self.performRefresh()
        }
        inFlightRefresh = task
        defer { inFlightRefresh = nil }

        try await task.value
    }

    private func performRefresh() async throws {
        guard let refreshToken = keychain.read(key: AppConstants.thrivnRefreshTokenKey),
              !refreshToken.isEmpty else {
            throw AIError.noAPIKey
        }

        struct Body: Encodable { let refresh_token: String }
        let url = baseURL.appendingPathComponent("v1/auth/refresh")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(Body(refresh_token: refreshToken))

        let (data, response) = try await session.data(for: request)

        // Special case: if the refresh token itself is invalid (401/403), the session
        // is dead. Clear local tokens so the next AIProviderFactory.provider() call
        // falls through to "noAPIKey" and the user is prompted to sign in again.
        if let http = response as? HTTPURLResponse, (http.statusCode == 401 || http.statusCode == 403) {
            clearLocalTokens()
            throw AIError.noAPIKey
        }
        try validateHTTPResponse(response, data: data)

        let envelope = try Self.decoder.decode(RefreshEnvelope.self, from: data)
        try persistTokens(
            accessToken: envelope.data.access_token,
            refreshToken: envelope.data.refresh_token
        )
    }

    /// Persist tokens to Keychain with `whenUnlockedThisDeviceOnly` protection.
    /// Throws if the Keychain write fails so the caller can surface the error
    /// instead of returning success with stale credentials.
    private func persistTokens(accessToken: String, refreshToken: String) throws {
        let savedAccess = keychain.save(
            key: AppConstants.thrivnAccessTokenKey,
            value: accessToken,
            protection: .whenUnlockedThisDeviceOnly
        )
        let savedRefresh = keychain.save(
            key: AppConstants.thrivnRefreshTokenKey,
            value: refreshToken,
            protection: .whenUnlockedThisDeviceOnly
        )
        guard savedAccess && savedRefresh else {
            throw AIError.apiError(
                statusCode: 0,
                message: "Couldn't store credentials. Please try again."
            )
        }
    }

    /// Clear stored tokens locally without contacting the server.
    /// Used when the server tells us the session is permanently expired.
    private func clearLocalTokens() {
        keychain.delete(key: AppConstants.thrivnAccessTokenKey)
        keychain.delete(key: AppConstants.thrivnRefreshTokenKey)
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
        let encodedBody = try Self.encoder.encode(body)

        // Try once. On 401, refresh once and retry. If that 401s again the session
        // is permanently dead — refreshTokens() already cleared the local tokens.
        do {
            return try await performChatRequest(url: url, encodedBody: encodedBody)
        } catch AIError.apiError(statusCode: 401, _) {
            try await refreshTokens()
            do {
                return try await performChatRequest(url: url, encodedBody: encodedBody)
            } catch AIError.apiError(statusCode: 401, _) {
                // Second 401 after refresh = session unrecoverable
                clearLocalTokens()
                throw AIError.noAPIKey
            }
        }
    }

    private func performChatRequest(url: URL, encodedBody: Data) async throws -> AIResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.httpBody = encodedBody

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
