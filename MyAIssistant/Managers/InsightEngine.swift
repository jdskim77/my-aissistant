import Foundation
import Observation
import SwiftData

@Observable @MainActor
final class InsightEngine {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    struct Insight: Identifiable {
        let id = UUID()
        let text: String
        let icon: String      // SF Symbol name
        let dimension: String  // physical, mental, emotional, spiritual, general
    }

    /// Generate today's micro-insight based on recent patterns.
    /// Returns nil if there isn't enough data (< 5 tasks or < 3 check-ins in the last 14 days).
    func todayInsight() -> Insight? {
        let insights = generateAllInsights()
        guard !insights.isEmpty else { return nil }

        // Deterministic daily selection cached per ordinal day so the chosen
        // insight is stable even if the available pool grows mid-day.
        let daySeed = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let cacheKey = "insightEngine.cachedIndex.\(daySeed)"
        let defaults = UserDefaults.standard
        let cachedIndex = defaults.object(forKey: cacheKey) as? Int
        if let cachedIndex, cachedIndex >= 0, cachedIndex < insights.count {
            return insights[cachedIndex]
        }
        let index = daySeed % insights.count
        defaults.set(index, forKey: cacheKey)
        return insights[index]
    }

    /// Generate all available insights from current data.
    private func generateAllInsights() -> [Insight] {
        var insights: [Insight] = []

        // Need data from the last 14 days to generate meaningful insights
        let calendar = Calendar.current
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: Date()) ?? Date()

        // Fetch recent tasks
        var taskDescriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { $0.date >= twoWeeksAgo }
        )
        taskDescriptor.fetchLimit = 500
        let recentTasks = (try? modelContext.fetch(taskDescriptor)) ?? []

        // Fetch recent check-ins
        var checkInDescriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate<CheckInRecord> { $0.date >= twoWeeksAgo }
        )
        checkInDescriptor.fetchLimit = 500
        let recentCheckIns = (try? modelContext.fetch(checkInDescriptor)) ?? []

        // Fetch all habits (active ones filtered below)
        var habitDescriptor = FetchDescriptor<HabitItem>()
        habitDescriptor.fetchLimit = 100
        let habits = (try? modelContext.fetch(habitDescriptor)) ?? []

        guard recentTasks.count >= 5 || recentCheckIns.count >= 3 else {
            return [] // Not enough data yet
        }

        // === INSIGHT GENERATORS ===

        // 1. Productivity by day of week
        if let bestDay = bestProductivityDay(tasks: recentTasks) {
            insights.append(Insight(
                text: "You complete the most tasks on \(bestDay). Your sweet spot!",
                icon: "chart.bar.fill",
                dimension: "mental"
            ))
        }

        // 2. Morning vs afternoon productivity
        if let timeInsight = productivityByTimeOfDay(tasks: recentTasks) {
            insights.append(timeInsight)
        }

        // 3. Mood-productivity correlation
        if let moodInsight = moodProductivityLink(tasks: recentTasks, checkIns: recentCheckIns) {
            insights.append(moodInsight)
        }

        // 4. Streak encouragement (uses a wider fetch so streaks > 14 days aren't capped)
        if let streakInsight = streakInsight() {
            insights.append(streakInsight)
        }

        // 5. Habit consistency
        if let habitInsight = habitConsistencyInsight(habits: habits) {
            insights.append(habitInsight)
        }

        // 6. Check-in mood trend
        if let moodTrend = moodTrendInsight(checkIns: recentCheckIns) {
            insights.append(moodTrend)
        }

        // 7. Completion rate change
        if let rateInsight = completionRateInsight(tasks: recentTasks) {
            insights.append(rateInsight)
        }

        // 8. Energy pattern
        if let energyInsight = energyPatternInsight(checkIns: recentCheckIns) {
            insights.append(energyInsight)
        }

        return insights
    }

    // MARK: - Individual Insight Generators

    private func bestProductivityDay(tasks: [TaskItem]) -> String? {
        let completed = tasks.filter { $0.done }
        guard completed.count >= 5 else { return nil }

        let calendar = Calendar.current
        var countByDay: [Int: Int] = [:]
        for task in completed {
            let weekday = calendar.component(.weekday, from: task.date)
            countByDay[weekday, default: 0] += 1
        }

        // Sort by count desc, weekday asc for deterministic tie-breaking
        let sorted = countByDay.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }
        guard let best = sorted.first, best.value >= 2 else { return nil }

        let dayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return dayNames[best.key]
    }

    private func productivityByTimeOfDay(tasks: [TaskItem]) -> Insight? {
        let completed = tasks.filter { $0.done }
        guard completed.count >= 5 else { return nil }

        let calendar = Calendar.current
        var morning = 0, afternoon = 0
        for task in completed {
            let hour = calendar.component(.hour, from: task.date)
            if hour < 12 { morning += 1 } else { afternoon += 1 }
        }

        let total = morning + afternoon
        guard total >= 5 else { return nil }

        let morningPct = Double(morning) / Double(total)
        if morningPct > 0.65 {
            return Insight(text: "You're a morning powerhouse — \(Int(morningPct * 100))% of tasks done before noon.", icon: "sunrise.fill", dimension: "physical")
        } else if morningPct < 0.35 {
            return Insight(text: "You hit your stride in the afternoon — \(Int((1 - morningPct) * 100))% of tasks done after noon.", icon: "sunset.fill", dimension: "physical")
        }
        return nil
    }

    private func moodProductivityLink(tasks: [TaskItem], checkIns: [CheckInRecord]) -> Insight? {
        // Check if high-mood days correlate with more task completions
        var moodByDay: [String: [Int]] = [:]
        var tasksByDay: [String: Int] = [:]

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        for ci in checkIns {
            if let mood = ci.mood {
                let key = fmt.string(from: ci.date)
                moodByDay[key, default: []].append(mood)
            }
        }

        for task in tasks where task.done {
            let key = fmt.string(from: task.date)
            tasksByDay[key, default: 0] += 1
        }

        // Calculate averages for high vs low mood days
        var highMoodTasks: [Int] = []
        var lowMoodTasks: [Int] = []

        for (day, moods) in moodByDay {
            let avgMood = Double(moods.reduce(0, +)) / Double(moods.count)
            let completed = tasksByDay[day] ?? 0
            if avgMood >= 4 { highMoodTasks.append(completed) }
            else if avgMood <= 2 { lowMoodTasks.append(completed) }
        }

        guard highMoodTasks.count >= 2, lowMoodTasks.count >= 2 else { return nil }

        let highAvg = Double(highMoodTasks.reduce(0, +)) / Double(highMoodTasks.count)
        let lowAvg = Double(lowMoodTasks.reduce(0, +)) / Double(lowMoodTasks.count)

        // Require a meaningful baseline so we don't divide by ~0 and report "47x".
        guard lowAvg >= 1.0, highAvg > lowAvg * 1.5 else { return nil }
        let raw = highAvg / lowAvg
        let capped = min(raw, 5.0)
        let multiplier = String(format: "%.1f", capped)
        return Insight(text: "You're \(multiplier)x more productive on days you rate your mood highly.", icon: "face.smiling.fill", dimension: "emotional")
    }

    private func streakInsight() -> Insight? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Wider fetch (1 year) so we don't artificially cap the streak at 14.
        let oneYearAgo = calendar.date(byAdding: .day, value: -365, to: today) ?? today
        var descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { $0.date >= oneYearAgo && $0.done == true }
        )
        descriptor.fetchLimit = 2000
        let completedTasks = (try? modelContext.fetch(descriptor)) ?? []

        var streak = 0
        var checkDate = today
        while true {
            let hasCompletion = completedTasks.contains { calendar.isDate($0.date, inSameDayAs: checkDate) }
            if !hasCompletion {
                if calendar.isDate(checkDate, inSameDayAs: today) {
                    checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
                    continue
                }
                break
            }
            streak += 1
            if streak > 365 { break }
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        if streak >= 3 && streak < 7 {
            return Insight(text: "\(streak) days active in a row. You're building momentum!", icon: "flame.fill", dimension: "general")
        } else if streak >= 7 && streak < 21 {
            return Insight(text: "\(streak)-day streak! Research says 21 days builds a habit — you're \(Int(Double(streak) / 21.0 * 100))% there.", icon: "flame.fill", dimension: "general")
        } else if streak >= 21 {
            return Insight(text: "\(streak) days strong. This isn't a streak anymore — it's who you are.", icon: "star.fill", dimension: "general")
        }
        return nil
    }

    private func habitConsistencyInsight(habits: [HabitItem]) -> Insight? {
        let activeHabits = habits.filter { $0.archivedAt == nil }
        guard !activeHabits.isEmpty else { return nil }

        // Find the habit with the best completion rate
        let best = activeHabits.max(by: { $0.completionRate() < $1.completionRate() })
        guard let best, best.completionRate() >= 0.7 else { return nil }

        let pct = Int(best.completionRate() * 100)
        return Insight(text: "\(best.title) at \(pct)% consistency. That's dedication.", icon: "checkmark.seal.fill", dimension: "general")
    }

    private func moodTrendInsight(checkIns: [CheckInRecord]) -> Insight? {
        let withMood = checkIns.filter { $0.mood != nil }.sorted { $0.date < $1.date }
        guard withMood.count >= 7 else { return nil }

        let recent = Array(withMood.suffix(7))
        let older = Array(withMood.prefix(7))

        let recentAvg = Double(recent.compactMap(\.mood).reduce(0, +)) / Double(recent.count)
        let olderAvg = Double(older.compactMap(\.mood).reduce(0, +)) / Double(older.count)

        if recentAvg > olderAvg + 0.5 {
            return Insight(text: "Your mood has been trending up this week. Something's working — keep it going!", icon: "arrow.up.right", dimension: "emotional")
        } else if recentAvg < olderAvg - 0.5 {
            return Insight(text: "Your mood dipped recently. Be gentle with yourself — dips are normal and temporary.", icon: "heart.fill", dimension: "emotional")
        }
        return nil
    }

    private func completionRateInsight(tasks: [TaskItem]) -> Insight? {
        let calendar = Calendar.current
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: Date()) ?? Date()

        let thisWeek = tasks.filter { $0.date >= oneWeekAgo }
        let lastWeek = tasks.filter { $0.date >= twoWeeksAgo && $0.date < oneWeekAgo }

        guard thisWeek.count >= 3, lastWeek.count >= 3 else { return nil }

        let thisRate = Double(thisWeek.filter(\.done).count) / Double(thisWeek.count)
        let lastRate = Double(lastWeek.filter(\.done).count) / Double(lastWeek.count)

        if thisRate > lastRate + 0.15 {
            let pct = Int(thisRate * 100)
            return Insight(text: "Completion rate is up to \(pct)% this week — you're leveling up.", icon: "arrow.up.circle.fill", dimension: "mental")
        }
        return nil
    }

    private func energyPatternInsight(checkIns: [CheckInRecord]) -> Insight? {
        let withEnergy = checkIns.filter { $0.energyLevel != nil }
        guard withEnergy.count >= 5 else { return nil }

        let calendar = Calendar.current
        var morningEnergy: [Int] = []
        var eveningEnergy: [Int] = []

        for ci in withEnergy {
            guard let energy = ci.energyLevel else { continue }
            let hour = calendar.component(.hour, from: ci.date)
            if hour < 12 { morningEnergy.append(energy) }
            else if hour >= 17 { eveningEnergy.append(energy) }
        }

        guard morningEnergy.count >= 2, eveningEnergy.count >= 2 else { return nil }

        let morningAvg = Double(morningEnergy.reduce(0, +)) / Double(morningEnergy.count)
        let eveningAvg = Double(eveningEnergy.reduce(0, +)) / Double(eveningEnergy.count)

        if morningAvg > eveningAvg + 0.8 {
            return Insight(text: "Your energy peaks in the morning. Schedule your hardest tasks before noon.", icon: "bolt.fill", dimension: "physical")
        } else if eveningAvg > morningAvg + 0.8 {
            return Insight(text: "You come alive in the evening. Use that second wind for creative work.", icon: "moon.stars.fill", dimension: "physical")
        }
        return nil
    }
}
