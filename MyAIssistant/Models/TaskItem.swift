import Foundation
import SwiftData

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

    init(
        id: String = UUID().uuidString,
        title: String,
        category: TaskCategory,
        priority: TaskPriority,
        date: Date,
        done: Bool = false,
        icon: String,
        notes: String = ""
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
    }
}
