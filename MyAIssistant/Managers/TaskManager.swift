import Foundation
import SwiftData
import SwiftUI

@MainActor
final class TaskManager: ObservableObject {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - CRUD

    func addTask(_ task: TaskItem) {
        modelContext.insert(task)
        try? modelContext.save()
    }

    func toggleCompletion(_ task: TaskItem) {
        task.done.toggle()
        task.completedAt = task.done ? Date() : nil
        try? modelContext.save()
    }

    func deleteTask(_ task: TaskItem) {
        modelContext.delete(task)
        try? modelContext.save()
    }

    // MARK: - Queries

    func todayTasks() -> [TaskItem] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= startOfDay && $0.date < endOfDay },
            sortBy: [SortDescriptor(\TaskItem.priorityRaw)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func upcomingTasks(limit: Int = 50) -> [TaskItem] {
        let startOfDay = Calendar.current.startOfDay(for: Date())

        var descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= startOfDay && $0.done == false },
            sortBy: [SortDescriptor(\TaskItem.date)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func highPriorityUpcoming(limit: Int = 3) -> [TaskItem] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let highRaw = TaskPriority.high.rawValue

        var descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= startOfDay && $0.done == false && $0.priorityRaw == highRaw },
            sortBy: [SortDescriptor(\TaskItem.date)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func allTasks() -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(
            sortBy: [SortDescriptor(\TaskItem.date)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func tasksGroupedByDate(category: TaskCategory? = nil) -> [(date: Date, tasks: [TaskItem])] {
        let tasks: [TaskItem]
        if let category {
            let catRaw = category.rawValue
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.categoryRaw == catRaw },
                sortBy: [SortDescriptor(\TaskItem.date)]
            )
            tasks = (try? modelContext.fetch(descriptor)) ?? []
        } else {
            tasks = allTasks()
        }

        let grouped = Dictionary(grouping: tasks) { task in
            Calendar.current.startOfDay(for: task.date)
        }

        return grouped
            .map { (date: $0.key, tasks: $0.value.sorted { $0.priority.sortOrder < $1.priority.sortOrder }) }
            .sorted { $0.date < $1.date }
    }

    func tasksForCheckIn(_ checkIn: CheckInTime) -> [TaskItem] {
        let today = todayTasks()
        switch checkIn {
        case .morning:
            return today.filter { !$0.done }
        case .midday:
            return today
        case .afternoon:
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            let tomorrowStart = Calendar.current.startOfDay(for: tomorrow)
            let tomorrowEnd = Calendar.current.date(byAdding: .day, value: 1, to: tomorrowStart)!
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.date >= tomorrowStart && $0.date < tomorrowEnd },
                sortBy: [SortDescriptor(\TaskItem.priorityRaw)]
            )
            let tomorrowTasks = (try? modelContext.fetch(descriptor)) ?? []
            return today + tomorrowTasks
        case .night:
            return Array(upcomingTasks(limit: 5))
        }
    }

    // MARK: - Stats

    var completedTodayCount: Int {
        todayTasks().filter(\.done).count
    }

    var todayTaskCount: Int {
        todayTasks().count
    }

    // MARK: - Calendar Sync

    /// Whether a task was imported from an external calendar.
    func isCalendarImported(_ task: TaskItem) -> Bool {
        task.externalCalendarID != nil
    }

    /// Calendar source label for imported tasks.
    func calendarSourceLabel(_ task: TaskItem) -> String? {
        guard let extID = task.externalCalendarID else { return nil }
        if extID.hasPrefix("google:") { return "Google" }
        return "Calendar"
    }

    // MARK: - AI Context

    func scheduleSummary() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return allTasks().map { task in
            let status = task.done ? "✓" : "○"
            let dateStr = formatter.string(from: task.date)
            return "\(status) \(dateStr): \(task.title) [\(task.priority.rawValue)] (\(task.category.rawValue))"
        }.joined(separator: "\n")
    }

    // MARK: - Completion Rate

    func completionRate() -> Int {
        let tasks = allTasks()
        guard !tasks.isEmpty else { return 0 }
        let done = tasks.filter(\.done).count
        return Int(Double(done) / Double(tasks.count) * 100)
    }
}
