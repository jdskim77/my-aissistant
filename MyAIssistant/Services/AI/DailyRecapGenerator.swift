import Foundation
import SwiftData
import os.log

/// Generates personalized AI insight messages after check-ins.
/// Uses Haiku for fast, cost-effective generation.
@MainActor
final class DailyRecapGenerator {
    private let modelContext: ModelContext
    private let keychainService: KeychainService

    // Injected managers for data assembly
    var patternEngine: PatternEngine?
    var balanceManager: BalanceManager?
    var taskManager: TaskManager?
    var chatManager: ChatManager?

    /// The conversation ID used for daily recap messages in the chat.
    static let conversationID = "daily-recap"

    init(modelContext: ModelContext, keychainService: KeychainService) {
        self.modelContext = modelContext
        self.keychainService = keychainService
    }

    // MARK: - Day Number

    /// How many days since the user's first-ever check-in. Day 1 = first day.
    func dayNumber() -> Int {
        let descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        guard let first = (try? modelContext.fetch(descriptor))?.first else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: first.date, to: Date()).day ?? 0
        return max(1, days + 1)
    }

    // MARK: - Generate Recap

    /// Generate and return a personalized daily recap message.
    /// Returns nil if generation fails or if there's no API key.
    func generate(
        currentTimeSlot: CheckInTime,
        userName: String?,
        subscriptionTier: SubscriptionTier
    ) async -> String? {
        let day = dayNumber()

        // Assemble today's check-in data
        let todaysCheckIns = fetchTodaysCheckIns()

        // Assemble task stats
        let todayTasks = taskManager?.todayTasks() ?? []
        let completedToday = todayTasks.filter { $0.done }.count
        let totalToday = todayTasks.count

        // Pattern stats
        let streak = patternEngine?.currentStreak() ?? 0
        let completionRate = patternEngine?.completionRate() ?? 0
        let moodTrend = formatMoodTrend()

        // Balance
        let balanceSummary = balanceManager?.balanceSummaryForAI() ?? ""

        // Previous recap topics (to avoid repetition)
        let previousTopics = fetchRecentRecapTopics(last: 3)

        // User focus preference
        let focusPreference = UserDefaults.standard.string(forKey: "dailyRecap_userFocusPreference")

        let prompt = AIPromptBuilder.dailyRecapPrompt(
            dayNumber: day,
            currentTimeSlot: currentTimeSlot.rawValue,
            userName: userName,
            userFocusPreference: focusPreference,
            todaysCheckIns: todaysCheckIns,
            tasksCompletedToday: completedToday,
            tasksTotalToday: totalToday,
            streak: streak,
            completionRate: completionRate,
            balanceSummary: balanceSummary,
            recentMoodTrend: moodTrend,
            previousRecapTopics: previousTopics
        )

        do {
            // Use the lightweight model for fast, cheap generation
            let provider = try AIProviderFactory.provider(
                for: subscriptionTier,
                useCase: .checkIn,  // Uses Haiku — fast and cheap
                keychain: keychainService
            )

            let response = try await provider.sendMessage(
                userMessage: "Generate my daily recap.",
                conversationHistory: [],
                systemPromptStable: prompt,
                systemPromptVolatile: ""
            )

            let recap = response.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            // Save to chat history for continuity
            chatManager?.insertLocalMessage(
                role: .assistant,
                content: recap,
                conversationID: Self.conversationID
            )

            AppLogger.ai.info("Daily recap generated: day \(day, privacy: .public), \(recap.count, privacy: .public) chars")
            Breadcrumb.add(category: "ai", message: "Daily recap generated (day \(day))")

            return recap
        } catch {
            AppLogger.ai.error("Daily recap generation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Data Assembly

    private func fetchTodaysCheckIns() -> [(slot: String, mood: Int, energy: Int, notes: String?)] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start

        var descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { $0.completed && $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        descriptor.fetchLimit = 10

        let records = (try? modelContext.fetch(descriptor)) ?? []
        return records.map { record in
            (
                slot: record.timeSlotRaw,
                mood: record.mood ?? 3,
                energy: record.energyLevel ?? 3,
                notes: record.notes
            )
        }
    }

    private func formatMoodTrend() -> String {
        guard let trend = patternEngine?.moodTrend(days: 7), !trend.isEmpty else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return trend.map { point in
            "\(formatter.string(from: point.date)): mood \(String(format: "%.1f", point.mood))"
        }.joined(separator: ", ")
    }

    private func fetchRecentRecapTopics(last count: Int) -> [String] {
        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.conversationID == "daily-recap" && $0.roleRaw == "assistant" },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = count

        let messages = (try? modelContext.fetch(descriptor)) ?? []
        // Extract a brief topic hint from each message (first 80 chars)
        return messages.map { String($0.content.prefix(80)) }
    }
}
