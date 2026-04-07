import Foundation

// MARK: - Suggestion Model

/// A single AI-generated task suggestion tied to the user's active Season Goal.
struct GoalTaskSuggestion: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let category: TaskCategory
    let priority: TaskPriority
    let durationMinutes: Int
    let rationale: String
    /// Emoji icon chosen by the AI to visually tag the suggestion.
    let icon: String

    init(
        id: UUID = UUID(),
        title: String,
        category: TaskCategory,
        priority: TaskPriority,
        durationMinutes: Int,
        rationale: String,
        icon: String
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.priority = priority
        self.durationMinutes = durationMinutes
        self.rationale = rationale
        self.icon = icon
    }
}

// MARK: - Errors

enum GoalTaskSuggesterError: LocalizedError {
    case parseFailed
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .parseFailed: return "Couldn't understand the suggestions from the AI. Please try again."
        case .emptyResponse: return "The AI returned no suggestions. Please try again."
        }
    }
}

// MARK: - Suggester Service

/// Produces 3 on-demand, calendar-ready task suggestions aimed at advancing the user's
/// active Season Goal intention. Isolated as its own actor — does network work off the
/// main thread and never touches SwiftUI state directly.
final actor GoalTaskSuggester {
    private let keychain: KeychainService
    private let tier: SubscriptionTier

    init(keychain: KeychainService, tier: SubscriptionTier) {
        self.keychain = keychain
        self.tier = tier
    }

    // MARK: - Public API

    /// Asks the configured AI provider for 3 concrete task suggestions tied to a goal.
    /// - Parameters:
    ///   - goal: Active season goal (intention + dimension).
    ///   - recentTaskTitles: Titles the user has already scheduled/completed recently,
    ///     so the AI can avoid near-duplicates.
    ///   - scheduleSummary: This week's schedule summary (to avoid double-booking).
    /// - Returns: Exactly 3 suggestions (or fewer on parse-failure salvage).
    func suggestTasks(
        for goal: SeasonGoal,
        recentTaskTitles: [String],
        scheduleSummary: String
    ) async throws -> [GoalTaskSuggestion] {
        let provider = try AIProviderFactory.provider(for: tier, useCase: .chat, keychain: keychain)
        let systemPrompt = buildSystemPrompt(
            goal: goal,
            recentTaskTitles: recentTaskTitles,
            scheduleSummary: scheduleSummary
        )
        let userPrompt = "Suggest 3 tasks for this week that directly move me toward my goal. Respond with ONLY the JSON object."

        let response = try await provider.sendMessage(
            userMessage: userPrompt,
            conversationHistory: [],
            systemPrompt: systemPrompt
        )

        let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw GoalTaskSuggesterError.emptyResponse }

        return try Self.parse(content)
    }

    // MARK: - Prompt Building

    private func buildSystemPrompt(
        goal: SeasonGoal,
        recentTaskTitles: [String],
        scheduleSummary: String
    ) -> String {
        let dimensionLabel = goal.dimension.label
        let intention = goal.intention.isEmpty ? "(no explicit intention text)" : goal.intention
        let daysLeft = goal.daysRemaining
        let recentBlock: String
        if recentTaskTitles.isEmpty {
            recentBlock = "(none)"
        } else {
            recentBlock = recentTaskTitles.prefix(30).map { "- \($0)" }.joined(separator: "\n")
        }
        let scheduleBlock = scheduleSummary.isEmpty ? "(empty)" : scheduleSummary

        return """
        You are a concise planning assistant. The user has a 4-week Season Goal and wants \
        exactly 3 concrete, calendar-ready task suggestions that directly move them toward it.

        GOAL DIMENSION: \(dimensionLabel)
        INTENTION (verbatim): "\(intention)"
        DAYS REMAINING: \(daysLeft)

        THIS WEEK'S SCHEDULE (avoid double-booking, avoid duplicating):
        \(scheduleBlock)

        RECENT TASK TITLES (avoid near-duplicates):
        \(recentBlock)

        Rules:
        - Output EXACTLY 3 suggestions. No more, no fewer.
        - Each suggestion must be a small, specific, schedule-able action (not vague advice).
        - Provide variety — do NOT suggest 3 of the same type. Mix intensity and context.
        - Prefer short actions (15–60 minutes).
        - Each rationale must be ONE sentence explaining why it advances the intention.
        - Pick a fitting emoji icon per suggestion.
        - Use these category values ONLY: "Travel", "Errand", "Personal", "Work", "Health".
        - Use these priority values ONLY: "High", "Medium", "Low".
        - Respond with ONLY the JSON object below — no markdown, no prose, no code fences.

        JSON format:
        {
          "suggestions": [
            {
              "title": "string",
              "category": "Travel" | "Errand" | "Personal" | "Work" | "Health",
              "priority": "High" | "Medium" | "Low",
              "duration_minutes": integer,
              "rationale": "one-sentence string",
              "icon": "single emoji"
            }
          ]
        }
        """
    }

    // MARK: - Parsing

    /// Extracts JSON (even if wrapped in stray text/fences) and decodes suggestions.
    static func parse(_ content: String) throws -> [GoalTaskSuggestion] {
        let cleaned = stripCodeFences(content)
        guard let jsonRange = cleaned.range(of: "{", options: .literal),
              let endRange = cleaned.range(of: "}", options: .backwards) else {
            throw GoalTaskSuggesterError.parseFailed
        }
        let jsonSubstring = cleaned[jsonRange.lowerBound...endRange.lowerBound]
        guard let data = String(jsonSubstring).data(using: .utf8) else {
            throw GoalTaskSuggesterError.parseFailed
        }

        struct Envelope: Decodable {
            let suggestions: [Raw]
        }
        struct Raw: Decodable {
            let title: String
            let category: String
            let priority: String
            let duration_minutes: Int?
            let rationale: String
            let icon: String?
        }

        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else {
            throw GoalTaskSuggesterError.parseFailed
        }

        let parsed: [GoalTaskSuggestion] = envelope.suggestions.compactMap { raw in
            let category = TaskCategory(rawValue: raw.category) ?? .personal
            let priority = TaskPriority(rawValue: raw.priority) ?? .medium
            let duration = max(5, min(240, raw.duration_minutes ?? 30))
            let icon: String = {
                if let i = raw.icon, !i.isEmpty { return i }
                return "✨"
            }()
            let title = raw.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return GoalTaskSuggestion(
                title: title,
                category: category,
                priority: priority,
                durationMinutes: duration,
                rationale: raw.rationale.trimmingCharacters(in: .whitespacesAndNewlines),
                icon: icon
            )
        }

        guard !parsed.isEmpty else { throw GoalTaskSuggesterError.parseFailed }
        return Array(parsed.prefix(3))
    }

    private static func stripCodeFences(_ s: String) -> String {
        var result = s
        if result.contains("```") {
            result = result.replacingOccurrences(of: "```json", with: "")
            result = result.replacingOccurrences(of: "```JSON", with: "")
            result = result.replacingOccurrences(of: "```", with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
