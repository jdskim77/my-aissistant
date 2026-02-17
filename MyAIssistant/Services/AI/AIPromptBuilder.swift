import Foundation

enum AIPromptBuilder {

    // MARK: - Chat System Prompt

    static func chatSystemPrompt(
        scheduleSummary: String,
        completionRate: Int,
        streak: Int
    ) -> String {
        """
        You are a warm, motivational personal assistant. \
        Today is \(formattedToday()). Their stats: \(completionRate)% completion, \(streak)-day streak.

        Schedule:
        \(scheduleSummary.isEmpty ? "No tasks yet." : scheduleSummary)

        Be encouraging, concise, proactive. Celebrate wins. Surface urgent items. \
        Use emojis sparingly. No markdown headers or bullets.
        """
    }

    // MARK: - Check-in Prompt

    static func checkInPrompt(
        timeSlot: String,
        scheduleSummary: String,
        completionRate: Int,
        streak: Int,
        mood: Int?
    ) -> String {
        var prompt = """
        You are conducting a \(timeSlot) check-in with the user. \
        Today is \(formattedToday()). Their stats: \(completionRate)% completion, \(streak)-day streak.

        Schedule:
        \(scheduleSummary.isEmpty ? "No tasks yet." : scheduleSummary)

        """

        if let mood {
            prompt += "They rated their mood \(mood)/5. Acknowledge this warmly. "
        }

        prompt += """
        Greet them naturally for this time of day. \
        Highlight what's accomplished and what's ahead. \
        Be brief (2-3 sentences). Use emojis sparingly. No markdown.
        """

        return prompt
    }

    // MARK: - Weekly Review Prompt

    static func weeklyReviewPrompt(
        weekSummary: String,
        averageMood: Double?,
        totalTasks: Int,
        completedTasks: Int,
        streak: Int
    ) -> String {
        var prompt = """
        Generate a weekly review for the user. Week ending \(formattedToday()).

        Stats this week:
        - Tasks: \(completedTasks)/\(totalTasks) completed
        - Streak: \(streak) days
        """

        if let mood = averageMood {
            prompt += "\n- Average mood: \(String(format: "%.1f", mood))/5"
        }

        prompt += """

        Schedule this week:
        \(weekSummary.isEmpty ? "No tasks recorded." : weekSummary)

        Provide:
        1. A warm summary of their week (2-3 sentences)
        2. One specific pattern you noticed
        3. One actionable suggestion for next week

        Keep it under 150 words. Be encouraging. No markdown headers.
        """

        return prompt
    }

    // MARK: - Helpers

    private static func formattedToday() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: Date())
    }
}
