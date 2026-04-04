import AppIntents
import SwiftData

struct ToggleHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Habit"
    static var description = IntentDescription("Mark a habit as completed for today.")
    static var openAppWhenRun = false

    @Parameter(title: "Habit Name")
    var habitName: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentModelContainer.shared.mainContext
        let descriptor = FetchDescriptor<HabitItem>()
        let allHabits = (try? context.fetch(descriptor)) ?? []
        let active = allHabits.filter { $0.archivedAt == nil }

        // Find matching habit (case-insensitive partial match)
        let query = habitName.lowercased()
        guard let habit = active.first(where: { $0.title.lowercased().contains(query) }) else {
            let names = active.map(\.title).joined(separator: ", ")
            if active.isEmpty {
                return .result(dialog: "You don't have any habits set up yet. Open the app to create one.")
            }
            return .result(dialog: "I couldn't find a habit matching \"\(habitName)\". Your habits are: \(names)")
        }

        let today = Calendar.current.startOfDay(for: Date())
        let wasCompleted = habit.isCompletedOn(today)
        habit.toggleCompletion(for: today)
        context.safeSave()

        if wasCompleted {
            return .result(dialog: "Unmarked \"\(habit.title)\" for today.")
        } else {
            let streak = habit.currentStreak()
            var msg = "Done! \"\(habit.title)\" is logged for today."
            if streak > 1 {
                msg += " That's a \(streak)-day streak! 🔥"
            }
            return .result(dialog: "\(msg)")
        }
    }
}
