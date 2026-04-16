import Foundation
import SwiftData
import SwiftUI
import WidgetKit
import os.log

@Observable @MainActor
final class TaskManager {
    private let modelContext: ModelContext
    var calendarSyncManager: CalendarSyncManager?
    var balanceManager: BalanceManager?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - CRUD

    func addTask(_ task: TaskItem) {
        modelContext.insert(task)
        modelContext.safeSave()
        AppLogger.tasks.info("Task added: \(task.id, privacy: .public) title=\(task.title, privacy: .private)")
        Breadcrumb.add(category: "tasks", message: "Added task")
        updateWidgetData()
    }

    func toggleCompletion(_ task: TaskItem) {
        task.done.toggle()
        task.completedAt = task.done ? Date() : nil
        AppLogger.tasks.info("Task \(task.done ? "completed" : "uncompleted", privacy: .public): \(task.id, privacy: .public)")
        Breadcrumb.add(category: "tasks", message: task.done ? "Completed task" : "Uncompleted task")

        // Sync completion state back to Apple Reminders (two-way sync)
        calendarSyncManager?.syncTaskCompletionToReminder(task)

        // Auto-generate next recurring instance when marking done
        if task.done, task.recurrence != .none,
           let nextDate = task.recurrence.nextDate(after: task.date) {
            let next = TaskItem(
                title: task.title,
                category: task.category,
                priority: task.priority,
                date: nextDate,
                icon: task.icon,
                notes: task.notes,
                recurrence: task.recurrence
            )
            // D-06 fix: clone gets NO externalCalendarID — it's a new independent task
            modelContext.insert(next)
        }

        modelContext.safeSave()
        updateWidgetData()
    }

    func deleteTask(_ task: TaskItem) {
        AppLogger.tasks.info("Task deleted: \(task.id, privacy: .public)")
        Breadcrumb.add(category: "tasks", message: "Deleted task")
        modelContext.delete(task)
        modelContext.safeSave()
        updateWidgetData()
    }

    func rescheduleTask(_ task: TaskItem, to newDate: Date) {
        let calendar = Calendar.current
        let oldComponents = calendar.dateComponents([.hour, .minute], from: task.date)
        var newComponents = calendar.dateComponents([.year, .month, .day], from: newDate)
        newComponents.hour = oldComponents.hour
        newComponents.minute = oldComponents.minute
        task.date = calendar.date(from: newComponents) ?? newDate
        modelContext.safeSave()
        updateWidgetData()
    }

    // MARK: - Conversation Management

    func deleteConversationMessages(_ messages: [ChatMessage]) {
        for message in messages {
            modelContext.delete(message)
        }
        modelContext.safeSave()
    }

    // MARK: - Focus Sessions

    func saveFocusSession(_ session: FocusSession) {
        if session.modelContext == nil {
            modelContext.insert(session)
        }
        modelContext.safeSave()
    }

    // MARK: - Queries

    func todayTasks() -> [TaskItem] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.safeDate(byAdding: .day, value: 1, to: startOfDay)

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

    func findTask(byID id: String) -> TaskItem? {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
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
            let tomorrow = Calendar.current.safeDate(byAdding: .day, value: 1, to: Date())
            let tomorrowStart = Calendar.current.startOfDay(for: tomorrow)
            let tomorrowEnd = Calendar.current.safeDate(byAdding: .day, value: 1, to: tomorrowStart)
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

    /// Serializes near-term tasks for the AI system prompt.
    ///
    /// CRITICAL: the backend proxy caps `system` at 20,000 chars. With calendar
    /// sync on, a heavy user can easily produce 15k+ chars of schedule lines
    /// alone, pushing the full prompt past the limit and triggering a 422
    /// VALIDATION_ERROR. We enforce three caps:
    ///   1. Narrow window (yesterday → +7 days) — was -7 / +14
    ///   2. Hard task count cap (60) — priority order: today pending → today
    ///      done → near-future → past
    ///   3. External calendar IDs only on near-term tasks (next 48h). Far-out
    ///      events don't need IDs because the AI can't realistically act on
    ///      them in-thread.
    func scheduleSummary() -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.safeDate(byAdding: .day, value: 1, to: today)
        let nearWindowEnd = calendar.safeDate(byAdding: .day, value: 2, to: today)
        let windowStart = calendar.safeDate(byAdding: .day, value: -1, to: today)
        let windowEnd = calendar.safeDate(byAdding: .day, value: 7, to: today)

        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= windowStart && $0.date < windowEnd },
            sortBy: [SortDescriptor(\TaskItem.date)]
        )
        let tasks = (try? modelContext.fetch(descriptor)) ?? []

        // Prioritize: today pending > today done > future > yesterday.
        // Within each bucket, preserve date-ascending order.
        let todayPending = tasks.filter { !$0.done && $0.date >= today && $0.date < tomorrow }
        let todayDone = tasks.filter { $0.done && $0.date >= today && $0.date < tomorrow }
        let future = tasks.filter { $0.date >= tomorrow }
        let past = tasks.filter { $0.date < today }

        let maxTasks = 60
        let prioritized = Array((todayPending + todayDone + future + past).prefix(maxTasks))

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let lines = prioritized.map { task -> String in
            let status = task.done ? "✓" : "○"
            let dateStr = formatter.string(from: task.date)
            var line = "\(status) \(dateStr): \(task.title) [\(task.priority.rawValue)] (\(task.category.rawValue))"
            // IDs only for tasks within 48h — that's all the AI can meaningfully act on.
            if let extID = task.externalCalendarID, task.date < nearWindowEnd {
                line += " {id:\(extID)}"
            }
            return line
        }

        // Hint the AI when we've truncated so it doesn't pretend it saw everything.
        let truncatedTail = tasks.count > maxTasks
            ? "\n…and \(tasks.count - maxTasks) more tasks in the window (truncated for length)"
            : ""
        return lines.joined(separator: "\n") + truncatedTail
    }

    // MARK: - Completion Rate

    func completionRate() -> Int {
        let tasks = allTasks()
        guard !tasks.isEmpty else { return 0 }
        let done = tasks.filter(\.done).count
        return Int(Double(done) / Double(tasks.count) * 100)
    }

    // MARK: - Widget Data

    /// Snapshots current state to the shared App Group container for widgets to read.
    func updateWidgetData() {
        let today = todayTasks()
        let completed = today.filter(\.done).count

        // Compute streak from task data
        let streak = computeStreak()
        let pending = today.filter { !$0.done }
            .sorted { $0.priority.sortOrder < $1.priority.sortOrder }
            .prefix(3)
            .map { task -> WidgetTaskData in
                let hour = Calendar.current.component(.hour, from: task.date)
                let minute = Calendar.current.component(.minute, from: task.date)
                let timeStr: String? = (hour == 0 && minute == 0) ? nil : {
                    let f = DateFormatter()
                    f.dateFormat = "h:mm a"
                    return f.string(from: task.date)
                }()
                return WidgetTaskData(title: task.title, priority: task.priority.rawValue, time: timeStr)
            }

        // Load today's wisdom quote
        let quote = WisdomManager.todayQuote()

        let data = WidgetSharedData(
            tasksCompleted: completed,
            tasksTotal: today.count,
            topPending: pending,
            streakDays: streak,
            streakActive: streak > 0,
            quoteText: quote?.text,
            quoteAuthor: quote?.author,
            updatedAt: Date()
        )
        data.save()
        WidgetCenter.shared.reloadAllTimelines()

        // Query compass dimension scores so Watch rings render real data.
        // LifeDimension → Watch ring mapping: physical=body, mental=mind,
        // emotional=heart, spiritual=spirit. Nil bm = first-launch fallback.
        let compassScores: (body: Double, mind: Double, heart: Double, spirit: Double)? = {
            guard let scores = balanceManager?.weeklyScores() else { return nil }
            return (
                body:   scores[.physical]  ?? 5,
                mind:   scores[.mental]    ?? 5,
                heart:  scores[.emotional] ?? 5,
                spirit: scores[.spiritual] ?? 5
            )
        }()

        // Sync to Apple Watch
        WatchSyncManager.shared.syncSchedule(
            tasks: allTasks(),
            streak: streak,
            quoteText: quote?.text,
            quoteAuthor: quote?.author,
            compassScores: compassScores
        )
    }

    /// Streak with grace day for today and quiet days. Mirrors the canonical
    /// implementation in PatternEngine.currentStreak() — keep them in sync if
    /// either changes. (Both exist because TaskManager runs in widget contexts
    /// where injecting PatternEngine would add more wiring than is worth it.)
    private func computeStreak() -> Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.safeDate(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))
        var iterations = 0
        let maxLookback = 365
        while iterations < maxLookback {
            iterations += 1
            let nextDay = calendar.safeDate(byAdding: .day, value: 1, to: checkDate)

            let scheduledDescriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.date >= checkDate && $0.date < nextDay }
            )
            let scheduledCount = (try? modelContext.fetchCount(scheduledDescriptor)) ?? 0

            if scheduledCount == 0 {
                // Quiet day — doesn't break the streak
                checkDate = calendar.safeDate(byAdding: .day, value: -1, to: checkDate)
                continue
            }

            let completedDescriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.date >= checkDate && $0.date < nextDay && $0.done == true }
            )
            let completedCount = (try? modelContext.fetchCount(completedDescriptor)) ?? 0
            if completedCount > 0 {
                streak += 1
                checkDate = calendar.safeDate(byAdding: .day, value: -1, to: checkDate)
            } else {
                break
            }
        }
        return streak
    }
}

// MARK: - Shared Widget Data (mirrors widget target's WidgetData)

struct WidgetTaskData: Codable {
    let title: String
    let priority: String
    let time: String?
}

struct WidgetSharedData: Codable {
    let tasksCompleted: Int
    let tasksTotal: Int
    let topPending: [WidgetTaskData]
    let streakDays: Int
    let streakActive: Bool
    let quoteText: String?
    let quoteAuthor: String?
    let updatedAt: Date

    static let appGroupID = "group.com.myaissistant.shared"
    static let fileName = "widget-data.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    func save() {
        guard let url = Self.fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let encoded = try? encoder.encode(self) else { return }
        try? encoded.write(to: url, options: .atomic)
    }
}
