import AppIntents
import SwiftData

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a Task"
    static var description = IntentDescription("Add a new task to your schedule.")
    static var openAppWhenRun = false

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Date", default: Date())
    var date: Date

    @Parameter(title: "Priority", default: .medium)
    var priority: TaskPriorityEnum

    @Parameter(title: "Category", default: .personal)
    var category: TaskCategoryEnum

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentModelContainer.shared.mainContext
        let task = TaskItem(
            title: title,
            category: category.toModel,
            priority: priority.toModel,
            date: date,
            icon: category.toModel.icon
        )
        context.insert(task)
        try? context.save()

        let dateStr = date.formatted(date: .abbreviated, time: .shortened)
        return .result(dialog: "Added \"\(title)\" on \(dateStr).")
    }
}

// MARK: - AppEnum wrappers for Siri parameter resolution

enum TaskPriorityEnum: String, AppEnum {
    case high, medium, low

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Priority")
    static var caseDisplayRepresentations: [TaskPriorityEnum: DisplayRepresentation] = [
        .high: "High",
        .medium: "Medium",
        .low: "Low"
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
