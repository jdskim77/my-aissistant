import Foundation
import SwiftData

// MARK: - Recurrence

enum TaskRecurrence: String, CaseIterable, Identifiable, Codable {
    case none = "None"
    case daily = "Daily"
    case weekly = "Weekly"
    case biweekly = "Biweekly"
    case monthly = "Monthly"

    var id: String { rawValue }

    /// Calendar component offset for generating the next occurrence.
    func nextDate(after date: Date) -> Date? {
        let cal = Calendar.current
        switch self {
        case .none: return nil
        case .daily: return cal.date(byAdding: .day, value: 1, to: date)
        case .weekly: return cal.date(byAdding: .weekOfYear, value: 1, to: date)
        case .biweekly: return cal.date(byAdding: .weekOfYear, value: 2, to: date)
        case .monthly: return cal.date(byAdding: .month, value: 1, to: date)
        }
    }
}

@Model
final class TaskItem {
    var id: String
    var title: String
    var categoryRaw: String
    var priorityRaw: String
    var date: Date
    var done: Bool
    var icon: String
    var notes: String
    var createdAt: Date
    var completedAt: Date?
    var externalCalendarID: String?
    var recurrenceRaw: String?

    // MARK: - Computed enum accessors

    @Transient
    var category: TaskCategory {
        get { TaskCategory(rawValue: categoryRaw) ?? .personal }
        set { categoryRaw = newValue.rawValue }
    }

    @Transient
    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    @Transient
    var recurrence: TaskRecurrence {
        get { TaskRecurrence(rawValue: recurrenceRaw ?? "") ?? .none }
        set { recurrenceRaw = newValue == .none ? nil : newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        category: TaskCategory,
        priority: TaskPriority,
        date: Date,
        done: Bool = false,
        icon: String,
        notes: String = "",
        recurrence: TaskRecurrence = .none
    ) {
        self.id = id
        self.title = title
        self.categoryRaw = category.rawValue
        self.priorityRaw = priority.rawValue
        self.date = date
        self.done = done
        self.icon = icon
        self.notes = notes
        self.createdAt = Date()
        self.completedAt = done ? Date() : nil
        self.recurrenceRaw = recurrence == .none ? nil : recurrence.rawValue
    }
}
