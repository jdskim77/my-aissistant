#if os(watchOS)
import Foundation

/// Lightweight Claude API client for watchOS. Makes direct network calls.
actor WatchClaudeService {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"
    private let model = "claude-haiku-4-5-20251001" // Fast model for Watch latency

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f
    }()

    func sendQuery(prompt: String, scheduleContext: String, apiKey: String) async throws -> String {
        let systemPrompt = """
        You are a concise personal assistant on an Apple Watch. \
        Keep responses under 3 sentences. Be direct and actionable. \
        Today is \(Self.dateFormatter.string(from: Date())). \
        User's schedule: \(scheduleContext.isEmpty ? "No tasks loaded." : scheduleContext)
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 200,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WatchAIError.apiFailed
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw WatchAIError.invalidAPIKey
        case 429:
            throw WatchAIError.rateLimited
        case 500...599:
            throw WatchAIError.serverError
        default:
            throw WatchAIError.apiFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw WatchAIError.parseFailed
        }

        return text
    }
}

enum WatchAIError: LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case rateLimited
    case serverError
    case apiFailed
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "Watch chat needs an Anthropic API key. Open Thrivn on your iPhone → Settings → API Keys to add one."
        case .invalidAPIKey: return "Invalid API key. Update it in iPhone Settings."
        case .rateLimited: return "Too many requests. Wait a moment."
        case .serverError: return "AI service is temporarily down."
        case .apiFailed: return "Couldn't reach the AI. Try again."
        case .parseFailed: return "Got an unexpected response."
        }
    }
}

#endif
