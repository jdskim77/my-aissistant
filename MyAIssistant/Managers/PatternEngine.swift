import Foundation
import SwiftData
import SwiftUI

@MainActor
final class PatternEngine: ObservableObject {
    private let modelContext: ModelContext
    private let keychainService: KeychainService

    init(modelContext: ModelContext, keychainService: KeychainService = KeychainService()) {
        self.modelContext = modelContext
        self.keychainService = keychainService
    }

    // MARK: - Streak

    func currentStreak() -> Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        while true {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: checkDate)!

            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.date >= checkDate && $0.date < nextDay && $0.done == true }
            )
            let completedCount = (try? modelContext.fetchCount(descriptor)) ?? 0

            if completedCount > 0 {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                break
            }
        }

        return streak
    }

    // MARK: - Completion Rate

    func completionRate(days: Int = 30) -> Int {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date())!

        let totalDescriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= startDate }
        )
        let doneDescriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= startDate && $0.done == true }
        )

        let total = (try? modelContext.fetchCount(totalDescriptor)) ?? 0
        let done = (try? modelContext.fetchCount(doneDescriptor)) ?? 0

        guard total > 0 else { return 0 }
        return Int(Double(done) / Double(total) * 100)
    }

    // MARK: - Average Tasks Per Day

    func averageTasksPerDay(days: Int = 30) -> Double {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date())!

        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= startDate }
        )
        let total = (try? modelContext.fetchCount(descriptor)) ?? 0

        guard days > 0 else { return 0 }
        return Double(total) / Double(days)
    }

    // MARK: - Weekly Completions (Mon-Sun)

    func weeklyCompletions() -> [Int] {
        let calendar = Calendar.current
        var results = [Int](repeating: 0, count: 7)

        // Find this week's Monday
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: calendar.startOfDay(for: today))!

        for dayOffset in 0..<7 {
            let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: monday)!
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd && $0.done == true }
            )
            results[dayOffset] = (try? modelContext.fetchCount(descriptor)) ?? 0
        }

        return results
    }

    // MARK: - Check-in Consistency (last 7 days)

    func checkInConsistency() -> [Bool] {
        let calendar = Calendar.current
        var results = [Bool](repeating: false, count: 7)

        for dayOffset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: -(6 - dayOffset), to: calendar.startOfDay(for: Date()))!
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!

            let descriptor = FetchDescriptor<CheckInRecord>(
                predicate: #Predicate { $0.date >= day && $0.date < nextDay && $0.completed == true }
            )
            let count = (try? modelContext.fetchCount(descriptor)) ?? 0
            results[dayOffset] = count > 0
        }

        return results
    }

    // MARK: - Category Breakdown

    func categoryBreakdown() -> [(category: TaskCategory, done: Int, total: Int)] {
        TaskCategory.allCases.map { category in
            let catRaw = category.rawValue

            let totalDescriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.categoryRaw == catRaw }
            )
            let doneDescriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.categoryRaw == catRaw && $0.done == true }
            )

            let total = (try? modelContext.fetchCount(totalDescriptor)) ?? 0
            let done = (try? modelContext.fetchCount(doneDescriptor)) ?? 0

            return (category: category, done: done, total: total)
        }
    }

    // MARK: - Best Check-in Time

    func bestCheckInTime() -> String {
        var bestTime = CheckInTime.morning
        var bestCount = 0

        for timeSlot in CheckInTime.allCases {
            let slotRaw = timeSlot.rawValue
            let descriptor = FetchDescriptor<CheckInRecord>(
                predicate: #Predicate { $0.timeSlotRaw == slotRaw && $0.completed == true }
            )
            let count = (try? modelContext.fetchCount(descriptor)) ?? 0
            if count > bestCount {
                bestCount = count
                bestTime = timeSlot
            }
        }

        return bestTime.rawValue
    }

    // MARK: - Mood Trend (last N days)

    func moodTrend(days: Int = 14) -> [MoodDataPoint] {
        let calendar = Calendar.current
        var points: [MoodDataPoint] = []

        for dayOffset in (0..<days).reversed() {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: calendar.startOfDay(for: Date()))!
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!

            // Average mood from check-ins that day
            let checkInDescriptor = FetchDescriptor<CheckInRecord>(
                predicate: #Predicate { $0.date >= day && $0.date < nextDay && $0.completed == true }
            )
            let checkIns = (try? modelContext.fetch(checkInDescriptor)) ?? []
            let moods = checkIns.compactMap { $0.mood }
            guard !moods.isEmpty else { continue }
            let avgMood = Double(moods.reduce(0, +)) / Double(moods.count)

            // Completion rate that day
            let totalDescriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.date >= day && $0.date < nextDay }
            )
            let doneDescriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.date >= day && $0.date < nextDay && $0.done == true }
            )
            let total = (try? modelContext.fetchCount(totalDescriptor)) ?? 0
            let done = (try? modelContext.fetchCount(doneDescriptor)) ?? 0
            let rate = total > 0 ? Double(done) / Double(total) : 0

            points.append(MoodDataPoint(date: day, mood: avgMood, completionRate: rate))
        }

        return points
    }

    // MARK: - Mood-Productivity Correlation

    func moodProductivityCorrelation() -> Double? {
        let data = moodTrend(days: 30)
        guard data.count >= 5 else { return nil }

        let moods = data.map { $0.mood }
        let rates = data.map { $0.completionRate }
        let n = Double(data.count)

        let meanMood = moods.reduce(0, +) / n
        let meanRate = rates.reduce(0, +) / n

        var numerator = 0.0
        var denomMood = 0.0
        var denomRate = 0.0

        for i in 0..<data.count {
            let moodDiff = moods[i] - meanMood
            let rateDiff = rates[i] - meanRate
            numerator += moodDiff * rateDiff
            denomMood += moodDiff * moodDiff
            denomRate += rateDiff * rateDiff
        }

        let denominator = (denomMood * denomRate).squareRoot()
        guard denominator > 0 else { return nil }

        return numerator / denominator
    }

    // MARK: - Weekly Review Generation

    func generateWeeklyReview(tier: SubscriptionTier) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!

        // Gather week's stats
        let totalDescriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= weekAgo && $0.date < today }
        )
        let doneDescriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= weekAgo && $0.date < today && $0.done == true }
        )
        let totalTasks = (try? modelContext.fetchCount(totalDescriptor)) ?? 0
        let completedTasks = (try? modelContext.fetchCount(doneDescriptor)) ?? 0

        // Week's tasks for summary
        let tasksDescriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= weekAgo && $0.date < today },
            sortBy: [SortDescriptor(\TaskItem.date)]
        )
        let weekTasks = (try? modelContext.fetch(tasksDescriptor)) ?? []
        let weekSummary = weekTasks.map { "\($0.title) (\($0.done ? "done" : "pending"))" }.joined(separator: "\n")

        // Average mood from check-ins
        let checkInDescriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { $0.date >= weekAgo && $0.date < today && $0.completed == true }
        )
        let checkIns = (try? modelContext.fetch(checkInDescriptor)) ?? []
        let moods = checkIns.compactMap { $0.mood }
        let averageMood = moods.isEmpty ? nil : Double(moods.reduce(0, +)) / Double(moods.count)

        let streak = currentStreak()

        let systemPrompt = AIPromptBuilder.weeklyReviewPrompt(
            weekSummary: weekSummary,
            averageMood: averageMood,
            totalTasks: totalTasks,
            completedTasks: completedTasks,
            streak: streak
        )

        do {
            let provider = try AIProviderFactory.provider(
                for: tier,
                useCase: .weeklyReview,
                keychain: keychainService
            )

            let response = try await provider.sendMessage(
                userMessage: "Generate my weekly review.",
                conversationHistory: [],
                systemPrompt: systemPrompt
            )

            // Save as ChatMessage in the weekly-review conversation
            let reviewMessage = ChatMessage(
                role: .assistant,
                content: response.content,
                conversationID: "weekly-review"
            )
            modelContext.insert(reviewMessage)
            try? modelContext.save()
        } catch {
            // Silently fail — user can retry via the refresh button
        }
    }
}
