import Foundation
import SwiftData

struct DataSeeder {
    static func seedIfEmpty(context: ModelContext) {
        let descriptor = FetchDescriptor<TaskItem>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        seedStarterData(context: context)
    }

    // MARK: - Starter Data
    // Give new users clearly-labelled example tasks so the app feels alive
    // but they know these are samples they can delete.

    private static func seedStarterData(context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.safeDate(byAdding: .day, value: 1, to: today)

        let tasks = [
            // Today — mix of priorities and times
            TaskItem(
                title: "Example: Morning workout",
                category: .health,
                priority: .medium,
                date: calendar.date(bySettingHour: 7, minute: 30, second: 0, of: today) ?? today,
                icon: "🏃",
                notes: "This is a sample task — swipe left to delete it, or tap to edit."
            ),
            TaskItem(
                title: "Example: Team standup",
                category: .work,
                priority: .high,
                date: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today) ?? today,
                icon: "💼",
                notes: "Sample task. Try checking it off with the circle on the left!"
            ),
            TaskItem(
                title: "Example: Pick up groceries",
                category: .errand,
                priority: .low,
                date: calendar.date(bySettingHour: 17, minute: 0, second: 0, of: today) ?? today,
                icon: "🛒",
                notes: "Sample task. Add your own tasks using the + button in Schedule."
            ),
            // Tomorrow — so the schedule isn't empty when they swipe
            TaskItem(
                title: "Example: Project deadline",
                category: .work,
                priority: .high,
                date: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow) ?? tomorrow,
                icon: "📋",
                notes: "Sample task for tomorrow. Try the AI assistant — tap the mic on your tab bar!"
            ),
            TaskItem(
                title: "Example: Call dentist",
                category: .errand,
                priority: .medium,
                date: calendar.date(bySettingHour: 14, minute: 0, second: 0, of: tomorrow) ?? tomorrow,
                icon: "📞",
                notes: "Sample task. Connect your calendar in Settings to import real events."
            ),
        ]

        for task in tasks {
            context.insert(task)
        }
        context.safeSave()
    }
}
