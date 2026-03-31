import AppIntents
import SwiftData

struct TodayScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "Today's Schedule"
    static var description = IntentDescription("See what's on your schedule today.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentModelContainer.shared.mainContext
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.safeDate(byAdding: .day, value: 1, to: startOfDay)

        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= startOfDay && $0.date < endOfDay },
            sortBy: [SortDescriptor(\TaskItem.date)]
        )
        let tasks = (try? context.fetch(descriptor)) ?? []

        if tasks.isEmpty {
            return .result(dialog: "You have nothing scheduled for today. Enjoy the free time!")
        }

        let completed = tasks.filter(\.done).count
        let pending = tasks.count - completed

        var lines: [String] = []
        lines.append("You have \(tasks.count) task\(tasks.count == 1 ? "" : "s") today (\(completed) done, \(pending) remaining):")
        lines.append("")

        for task in tasks.prefix(8) {
            let status = task.done ? "✅" : "○"
            let time = formatTime(task.date)
            let pri = task.priority == .high ? " ❗" : ""
            lines.append("\(status) \(time) \(task.title)\(pri)")
        }

        if tasks.count > 8 {
            lines.append("...and \(tasks.count - 8) more")
        }

        return .result(dialog: "\(lines.joined(separator: "\n"))")
    }

    private func formatTime(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let minute = Calendar.current.component(.minute, from: date)
        if hour == 0 && minute == 0 { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
