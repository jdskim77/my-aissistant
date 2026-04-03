import Foundation
import SwiftData

// MARK: - Effort Level

enum EffortLevel: String, CaseIterable, Identifiable, Codable {
    case light = "Light"
    case moderate = "Moderate"
    case intense = "Intense"

    var id: String { rawValue }

    /// Effort points used in Life Compass scoring.
    var points: Int {
        switch self {
        case .light: return 1
        case .moderate: return 2
        case .intense: return 3
        }
    }

    var icon: String {
        switch self {
        case .light: return "leaf"
        case .moderate: return "flame"
        case .intense: return "bolt.fill"
        }
    }

    var label: String { rawValue }
}

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
    var dimensionRaw: String?
    var effortRaw: String?

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

    @Transient
    var dimension: LifeDimension? {
        get { dimensionRaw.flatMap { LifeDimension(rawValue: $0) } }
        set { dimensionRaw = newValue?.rawValue }
    }

    @Transient
    var effort: EffortLevel {
        get { EffortLevel(rawValue: effortRaw ?? "") ?? .moderate }
        set { effortRaw = newValue.rawValue }
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
