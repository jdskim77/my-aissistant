import AppIntents
import SwiftData

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a Task"
    static var description = IntentDescription("Add a new task to your schedule.")
    static var openAppWhenRun = false

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Date")
    var date: Date?

    @Parameter(title: "Priority")
    var priority: TaskPriorityEnum?

    @Parameter(title: "Category")
    var category: TaskCategoryEnum?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentModelContainer.shared.mainContext
        let resolvedDate = date ?? Date()
        let resolvedPriority = (priority ?? .medium).toModel
        let resolvedCategory = (category ?? .personal).toModel
        let task = TaskItem(
            title: title,
            category: resolvedCategory,
            priority: resolvedPriority,
            date: resolvedDate,
            icon: resolvedCategory.icon
        )
        context.insert(task)
        context.safeSave()

        let dateStr = resolvedDate.formatted(date: .abbreviated, time: .shortened)
        return .result(dialog: "Added \"\(title)\" on \(dateStr).")
    }
}

// MARK: - AppEnum wrappers for Siri parameter resolution

enum TaskPriorityEnum: String, AppEnum {
    case high, medium, low

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Priority")
    static var caseDisplayRepresentations: [TaskPriorityEnum: DisplayRepresentation] = [
        .high: "Must Do",
        .medium: "Should Do",
        .low: "Could Do"
    ]

    var toModel: TaskPriority {
        switch self {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }
}

enum TaskCategoryEnum: String, AppEnum {
    case travel, errand, personal, work, health

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Category")
    static var caseDisplayRepresentations: [TaskCategoryEnum: DisplayRepresentation] = [
        .travel: "Travel",
        .errand: "Errand",
        .personal: "Personal",
        .work: "Work",
        .health: "Health"
    ]

    var toModel: TaskCategory {
        switch self {
        case .travel: return .travel
        case .errand: return .errand
        case .personal: return .personal
        case .work: return .work
        case .health: return .health
        }
    }
}
