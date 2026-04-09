import Foundation
import SwiftData
import SwiftUI

@Observable @MainActor
final class PatternEngine {
    private let modelContext: ModelContext
    private let keychainService: KeychainService

    init(modelContext: ModelContext, keychainService: KeychainService = KeychainService()) {
        self.modelContext = modelContext
        self.keychainService = keychainService
    }

    // MARK: - Streak

    /// Streak with a "today is a grace day" rule.
    ///
    /// The previous implementation walked backward from today and required a
    /// completed task on the current day for the streak to be > 0. That meant
    /// a real 30-day streak would display as 0 the moment the user opened the
    /// app on a quiet Saturday with no tasks scheduled — and the streak-at-risk
    /// notification would fire for a streak the same code reported as zero.
    ///
    /// New rule:
    ///   - Today is always a grace day. The walk starts from yesterday.
    ///   - A day with NO tasks scheduled does NOT break the streak — only a
    ///     day where tasks existed and zero were completed counts as a break.
    ///     This matches user intuition: "I show up when there's something to
    ///     show up for."
    func currentStreak() -> Int {
        let calendar = Calendar.current
        var streak = 0
        // Start from yesterday — today is grace.
        var checkDate = calendar.safeDate(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))

        // Hard cap the walk so a misbehaving DB can't infinite-loop.
        let maxLookback = 365
        var iterations = 0

        while iterations < maxLookback {
            iterations += 1
            let nextDay = calendar.safeDate(byAdding: .day, value: 1, to: checkDate)

            // How many tasks were SCHEDULED for this day (regardless of done state)
            let scheduledDescriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.date >= checkDate && $0.date < nextDay }
            )
            let scheduledCount = (try? modelContext.fetchCount(scheduledDescriptor)) ?? 0

            if scheduledCount == 0 {
                // No tasks were scheduled — quiet day, doesn't break the streak
                checkDate = calendar.safeDate(byAdding: .day, value: -1, to: checkDate)
                continue
            }

            // Tasks existed — did the user complete at least one?
            let completedDescriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.date >= checkDate && $0.date < nextDay && $0.done == true }
            )
            let completedCount = (try? modelContext.fetchCount(completedDescriptor)) ?? 0

            if completedCount > 0 {
                streak += 1
                checkDate = calendar.safeDate(byAdding: .day, value: -1, to: checkDate)
            } else {
                // Active day with zero completed tasks → streak broken
                break
            }
        }

        return streak
    }

    // MARK: - Completion Rate

    func completionRate(days: Int = 30) -> Int {
        let calendar = Calendar.current
        let startDate = calendar.safeDate(byAdding: .day, value: -days, to: Date())

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
        let startDate = calendar.safeDate(byAdding: .day, value: -days, to: Date())

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
        let monday = calendar.safeDate(byAdding: .day, value: -daysFromMonday, to: calendar.startOfDay(for: today))

        for dayOffset in 0..<7 {
            let dayStart = calendar.safeDate(byAdding: .day, value: dayOffset, to: monday)
            let dayEnd = calendar.safeDate(byAdding: .day, value: 1, to: dayStart)

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
            let day = calendar.safeDate(byAdding: .day, value: -(6 - dayOffset), to: calendar.startOfDay(for: Date()))
            let nextDay = calendar.safeDate(byAdding: .day, value: 1, to: day)

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
            let day = calendar.safeDate(byAdding: .day, value: -dayOffset, to: calendar.startOfDay(for: Date()))
            let nextDay = calendar.safeDate(byAdding: .day, value: 1, to: day)

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

    // MARK: - Activity Tracking

    func recentActivities(days: Int = 30) -> [ActivityEntry] {
        let calendar = Calendar.current
        let startDate = calendar.safeDate(byAdding: .day, value: -days, to: Date())

        var descriptor = FetchDescriptor<ActivityEntry>(
            predicate: #Predicate { $0.date >= startDate },
            sortBy: [SortDescriptor(\ActivityEntry.date, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func activityCategorySummary(days: Int = 30) -> [(category: String, count: Int)] {
        let activities = recentActivities(days: days)
        var counts: [String: Int] = [:]
        for activity in activities {
            counts[activity.category, default: 0] += 1
        }
        return counts.map { (category: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    func activitySummaryText(days: Int = 30) -> String {
        let activities = recentActivities(days: days)
        guard !activities.isEmpty else { return "" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        let lines = activities.prefix(50).map { entry in
            "\(formatter.string(from: entry.date)): [\(entry.category)] \(entry.activity)"
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Activity Frequency & Timing

    /// Weekly frequency per activity category over the last N days.
    /// Returns e.g. [("Exercise", 3.5), ("Social", 1.2)] meaning 3.5 sessions/week on average.
    func activityWeeklyFrequency(days: Int = 28) -> [(category: String, perWeek: Double)] {
        let activities = recentActivities(days: days)
        guard !activities.isEmpty else { return [] }

        let weeks = max(Double(days) / 7.0, 1.0)
        var counts: [String: Int] = [:]
        for activity in activities {
            counts[activity.category, default: 0] += 1
        }

        return counts.map { (category: $0.key, perWeek: Double($0.value) / weeks) }
            .sorted { $0.perWeek > $1.perWeek }
    }

    /// Best (most common) hour of day per activity category.
    /// Returns e.g. [("Exercise", 8), ("Work", 10)] meaning Exercise typically at 8am.
    func bestTimePerCategory(days: Int = 28) -> [(category: String, hour: Int)] {
        let activities = recentActivities(days: days)
        guard !activities.isEmpty else { return [] }

        let calendar = Calendar.current
        var hoursByCategory: [String: [Int]] = [:]
        for activity in activities {
            let hour = calendar.component(.hour, from: activity.date)
            hoursByCategory[activity.category, default: []].append(hour)
        }

        return hoursByCategory.compactMap { category, hours in
            guard !hours.isEmpty else { return nil }
            // Find the mode (most frequent hour)
            let freq = Dictionary(grouping: hours, by: { $0 }).mapValues(\.count)
            guard let bestHour = freq.max(by: { $0.value < $1.value })?.key else { return nil }
            return (category: category, hour: bestHour)
        }.sorted { $0.category < $1.category }
    }

    /// Formatted pattern insights string for feeding into the AI system prompt.
    /// Combines frequency + timing into a concise, readable block.
    func patternInsightsText(days: Int = 28) -> String {
        let frequencies = activityWeeklyFrequency(days: days)
        let bestTimes = bestTimePerCategory(days: days)
        guard !frequencies.isEmpty else { return "" }

        let timeMap = Dictionary(uniqueKeysWithValues: bestTimes.map { ($0.category, $0.hour) })

        let lines = frequencies.prefix(10).map { entry in
            var line = "\(entry.category): ~\(String(format: "%.1f", entry.perWeek))x/week"
            if let hour = timeMap[entry.category] {
                let period = hour < 12 ? "am" : "pm"
                let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
                line += " (usually around \(displayHour)\(period))"
            }
            return line
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Weekly Review Generation

    func generateWeeklyReview(tier: SubscriptionTier) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekAgo = calendar.safeDate(byAdding: .day, value: -7, to: today)

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
            modelContext.safeSave()
        } catch {
            // Silently fail — user can retry via the refresh button
        }
    }
}
