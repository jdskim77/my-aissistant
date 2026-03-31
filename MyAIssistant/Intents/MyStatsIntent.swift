import AppIntents
import SwiftData

struct MyStatsIntent: AppIntent {
    static var title: LocalizedStringResource = "My Stats"
    static var description = IntentDescription("Check your streak, completion rate, and productivity stats.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentModelContainer.shared.mainContext
        let calendar = Calendar.current

        // Streak
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())
        while true {
            let nextDay = calendar.safeDate(byAdding: .day, value: 1, to: checkDate)
            let desc = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.date >= checkDate && $0.date < nextDay && $0.done == true }
            )
            let count = (try? context.fetchCount(desc)) ?? 0
            if count > 0 {
                streak += 1
                checkDate = calendar.safeDate(byAdding: .day, value: -1, to: checkDate)
            } else {
                break
            }
        }

        // Completion rate (30 days)
        let thirtyDaysAgo = calendar.safeDate(byAdding: .day, value: -30, to: Date())
        let totalDesc = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.date >= thirtyDaysAgo })
        let doneDesc = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.date >= thirtyDaysAgo && $0.done == true })
        let total = (try? context.fetchCount(totalDesc)) ?? 0
        let done = (try? context.fetchCount(doneDesc)) ?? 0
        let rate = total > 0 ? Int(Double(done) / Double(total) * 100) : 0

        // Today
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.safeDate(byAdding: .day, value: 1, to: startOfDay)
        let todayDesc = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.date >= startOfDay && $0.date < endOfDay })
        let todayDoneDesc = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.date >= startOfDay && $0.date < endOfDay && $0.done == true })
        let todayTotal = (try? context.fetchCount(todayDesc)) ?? 0
        let todayDone = (try? context.fetchCount(todayDoneDesc)) ?? 0

        // Habits
        let habitsDesc = FetchDescriptor<HabitItem>()
        let habits = (try? context.fetch(habitsDesc)) ?? []
        let activeHabits = habits.filter { $0.archivedAt == nil }
        let habitsToday = activeHabits.filter { $0.isCompletedOn(startOfDay) }.count

        var lines: [String] = []
        lines.append("Here's how you're doing:")
        lines.append("")
        if streak > 0 {
            lines.append("🔥 \(streak)-day streak")
        }
        lines.append("📊 \(rate)% completion rate (30 days)")
        lines.append("📅 Today: \(todayDone)/\(todayTotal) tasks done")
        if !activeHabits.isEmpty {
            lines.append("🌱 Habits: \(habitsToday)/\(activeHabits.count) completed today")
        }

        if streak == 0 {
            lines.append("\nComplete a task today to start a new streak!")
        } else if streak >= 7 {
            lines.append("\nAmazing consistency — keep it going!")
        }

        return .result(dialog: "\(lines.joined(separator: "\n"))")
    }
}
