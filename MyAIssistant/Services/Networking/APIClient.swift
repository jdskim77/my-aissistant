import Foundation

actor APIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
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
}
