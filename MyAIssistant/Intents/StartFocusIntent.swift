import AppIntents
import SwiftData

struct StartFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Focus Session"
    static var description = IntentDescription("Start a Pomodoro focus session.")
    static var openAppWhenRun = true // must open the app for the timer UI

    @Parameter(title: "Duration (minutes)", default: 25)
    var durationMinutes: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // The app will handle opening the FocusTimerView via a notification
        NotificationCenter.default.post(
            name: .startFocusSession,
            object: nil,
            userInfo: ["duration": durationMinutes]
        )

        return .result(dialog: "Starting a \(durationMinutes)-minute focus session. Stay focused!")
    }
}

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete a Task"
    static var description = IntentDescription("Mark a task as completed.")
    static var openAppWhenRun = false

    @Parameter(title: "Task Name")
    var taskName: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentModelContainer.shared.mainContext
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.safeDate(byAdding: .day, value: 1, to: startOfDay)

        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= startOfDay && $0.date < endOfDay && $0.done == false },
            sortBy: [SortDescriptor(\TaskItem.date)]
        )
        let tasks = (try? context.fetch(descriptor)) ?? []

        let query = taskName.lowercased()
        guard let task = tasks.first(where: { $0.title.lowercased().contains(query) }) else {
            if tasks.isEmpty {
                return .result(dialog: "You don't have any pending tasks for today.")
            }
            let names = tasks.prefix(5).map(\.title).joined(separator: ", ")
            return .result(dialog: "I couldn't find a task matching \"\(taskName)\". Today's pending tasks: \(names)")
        }

        task.done = true
        task.completedAt = Date()
        try? context.save()

        let remaining = tasks.count - 1
        var msg = "Completed \"\(task.title)\"!"
        if remaining > 0 {
            msg += " \(remaining) task\(remaining == 1 ? "" : "s") remaining today."
        } else {
            msg += " You're all done for today! 🎉"
        }

        return .result(dialog: "\(msg)")
    }
}

// MARK: - Notification for Focus Session

extension Notification.Name {
    static let startFocusSession = Notification.Name("startFocusSession")
}
