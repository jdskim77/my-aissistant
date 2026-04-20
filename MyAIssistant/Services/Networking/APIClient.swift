import Foundation

actor APIClient {
    private let session: URLSession

    /// Token-bucket rate limiter: allows burst of `bucketSize` then refills at `refillInterval`.
    private let bucketSize: Int
    private let refillInterval: TimeInterval
    private var tokens: Int
    private var lastRefill: Date

    init(
        session: URLSession? = nil,
        bucketSize: Int = 5,
        refillInterval: TimeInterval = 10
    ) {
        // Use a dedicated session with explicit timeouts for AI traffic.
        // URLSession.shared defaults to 60s request / 7d resource which can
        // leave a slow LLM request hanging long past when the user has given
        // up. These values fit streaming-completion latency for Claude.
        self.session = session ?? {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 120
            config.waitsForConnectivity = false
            return URLSession(configuration: config)
        }()
        self.bucketSize = bucketSize
        self.refillInterval = refillInterval
        self.tokens = bucketSize
        self.lastRefill = Date()
    }

    struct Response {
        let data: Data
        let statusCode: Int
    }

    /// Maximum number of retry attempts for rate-limited (429) or server error (5xx) responses.
    private let maxRetries = 3

    func post(
        url: URL,
        headers: [String: String],
        body: Data
    ) async throws -> Response {
        var lastResponse: Response?

        for attempt in 0..<maxRetries {
            try await consumeToken()

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw AIError.networkError(error)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIError.invalidResponse
            }

            let result = Response(data: data, statusCode: httpResponse.statusCode)

            // Retry on 429 (rate limited) or 5xx (server error), with exponential backoff
            if httpResponse.statusCode == 429 || (500...599).contains(httpResponse.statusCode) {
                lastResponse = result
                let delay = pow(2.0, Double(attempt)) // 1s, 2s, 4s
                AppLogger.ai.warning("API returned \(httpResponse.statusCode), retrying in \(delay)s (attempt \(attempt + 1)/\(self.maxRetries))")
                try await Task.sleep(for: .seconds(delay))
                continue
            }

            return result
        }

        // All retries exhausted — return the last response so caller can handle the error
        if let lastResponse {
            AppLogger.ai.error("API failed after \(self.maxRetries) retries with status \(lastResponse.statusCode)")
            return lastResponse
        }
        throw AIError.rateLimited
    }

    // MARK: - Rate Limiting

    private func consumeToken() async throws {
        refillTokens()
        if tokens > 0 {
            tokens -= 1
            return
        }
        // Wait for next refill then retry
        try await Task.sleep(for: .seconds(refillInterval))
        refillTokens()
        guard tokens > 0 else {
            // Local bucket exhaustion — surface as a network error rather
            // than `.rateLimited`. Reason: when the user is offline, the
            // network request never lands; the local throttle still runs
            // and used to throw `.rateLimited`, which ChatManager rendered
            // as "Too many requests." That's confusing ("I barely typed!")
            // and masks the real cause (no connectivity). Use networkError
            // so the user-facing copy stays "trouble connecting."
            throw AIError.networkError(NSError(
                domain: "APIClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Local throttle — try again in a few seconds."]
            ))
        }
        tokens -= 1
    }

    private func refillTokens() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)
        let refillCount = Int(elapsed / refillInterval)
        if refillCount > 0 {
            tokens = min(bucketSize, tokens + refillCount)
            lastRefill = now
        }
    }
}
