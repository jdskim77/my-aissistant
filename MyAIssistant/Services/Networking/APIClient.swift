import Foundation

actor APIClient {
    private let session: URLSession

    /// Token-bucket rate limiter: allows burst of `bucketSize` then refills at `refillInterval`.
    private let bucketSize: Int
    private let refillInterval: TimeInterval
    private var tokens: Int
    private var lastRefill: Date

    init(
        session: URLSession = .shared,
        bucketSize: Int = 5,
        refillInterval: TimeInterval = 10
    ) {
        self.session = session
        self.bucketSize = bucketSize
        self.refillInterval = refillInterval
        self.tokens = bucketSize
        self.lastRefill = Date()
    }

    struct Response {
        let data: Data
        let statusCode: Int
    }

    func post(
        url: URL,
        headers: [String: String],
        body: Data
    ) async throws -> Response {
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

        return Response(data: data, statusCode: httpResponse.statusCode)
    }

    // MARK: - Rate Limiting

    private mutating func consumeToken() async throws {
        refillTokens()
        if tokens > 0 {
            tokens -= 1
            return
        }
        // Wait for next refill then retry
        try await Task.sleep(for: .seconds(refillInterval))
        refillTokens()
        guard tokens > 0 else {
            throw AIError.rateLimited
        }
        tokens -= 1
    }

    private mutating func refillTokens() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)
        let refillCount = Int(elapsed / refillInterval)
        if refillCount > 0 {
            tokens = min(bucketSize, tokens + refillCount)
            lastRefill = now
        }
    }
}
