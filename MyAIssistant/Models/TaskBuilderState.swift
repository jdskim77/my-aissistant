import Foundation

enum TaskBuilderStep: String {
    case idle
    case title       // waiting for text input
    case priority    // show priority chips
    case date        // show date chips
    case time        // show time chips
    case category    // show category chips
    case confirm     // show summary + create/edit
}

struct TaskBuilderChip: Identifiable {
    let id = UUID()
    let label: String
    let icon: String?     // optional emoji prefix
    let value: String     // machine-readable value
}

@Observable
class TaskBuilderState {
    var step: TaskBuilderStep = .idle
    var title: String?
    var priority: TaskPriority = .medium
    var selectedDate: Date?
    var timeOfDay: String?   // "morning", "afternoon", "evening", nil
    var category: TaskCategory = .personal
    var isActive: Bool { step != .idle }

    // MARK: - Chips for current step

    var chips: [TaskBuilderChip] {
        switch step {
        case .idle:
            return []
        case .title:
            return []  // Text input, no chips
        case .priority:
            return [
                TaskBuilderChip(label: "High", icon: "🔴", value: "High"),
                TaskBuilderChip(label: "Medium", icon: "🟡", value: "Medium"),
                TaskBuilderChip(label: "Low", icon: "🟢", value: "Low"),
            ]
        case .date:
            return [
                TaskBuilderChip(label: "Today", icon: nil, value: "today"),
                TaskBuilderChip(label: "Tomorrow", icon: nil, value: "tomorrow"),
                TaskBuilderChip(label: "This Week", icon: nil, value: "thisWeek"),
            ]
        case .time:
            return [
                TaskBuilderChip(label: "Morning", icon: "☀️", value: "morning"),
                TaskBuilderChip(label: "Afternoon", icon: "🌤", value: "afternoon"),
                TaskBuilderChip(label: "Evening", icon: "🌅", value: "evening"),
                TaskBuilderChip(label: "No Time", icon: nil, value: "none"),
            ]
        case .category:
            return [
                TaskBuilderChip(label: "Work", icon: "💼", value: "Work"),
                TaskBuilderChip(label: "Health", icon: "🏃", value: "Health"),
                TaskBuilderChip(label: "Personal", icon: "🏠", value: "Personal"),
                TaskBuilderChip(label: "Errand", icon: "🛒", value: "Errand"),
            ]
        case .confirm:
            return [
                TaskBuilderChip(label: "Create Task", icon: "✅", value: "create"),
                TaskBuilderChip(label: "Edit", icon: "✏️", value: "edit"),
                TaskBuilderChip(label: "Cancel", icon: nil, value: "cancel"),
            ]
        }
    }

    // MARK: - Prompt for current step

    var promptMessage: String {
        switch step {
        case .idle: return ""
        case .title: return "What's the task? Type or speak the title."
        case .priority: return "What priority?"
        case .date: return "When should this be done?"
        case .time: return "What time of day?"
        case .category: return "What category?"
        case .confirm: return confirmationSummary
        }
    }

    var confirmationSummary: String {
        let dateStr: String
        if let d = selectedDate {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            dateStr = fmt.string(from: d)
        } else {
            dateStr = "No date"
        }
        let timeStr: String
        if let tod = timeOfDay {
            switch tod {
            case "morning": timeStr = " (Morning)"
            case "afternoon": timeStr = " (Afternoon)"
            case "evening": timeStr = " (Evening)"
            default: timeStr = ""
            }
        } else {
            timeStr = ""
        }
        return "Here's your task:\n\n📋 \(title ?? "Untitled")\n📅 \(dateStr)\(timeStr)\n⚡ \(priority.rawValue) priority\n🏷 \(category.rawValue)\n\nLook good?"
    }

    // MARK: - Process chip selection

    func selectChip(_ chip: TaskBuilderChip) {
        switch step {
        case .priority:
            priority = TaskPriority(rawValue: chip.value) ?? .medium
            step = .date
        case .date:
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            switch chip.value {
            case "today": selectedDate = today
            case "tomorrow": selectedDate = cal.date(byAdding: .day, value: 1, to: today)
            case "thisWeek": selectedDate = cal.date(byAdding: .day, value: 3, to: today)
            default: selectedDate = today
            }
            step = .time
        case .time:
            timeOfDay = chip.value == "none" ? nil : chip.value
            if let date = selectedDate, let tod = timeOfDay {
                let hour: Int
                switch tod {
                case "morning": hour = 9
                case "afternoon": hour = 14
                case "evening": hour = 18
                default: hour = 12
                }
                selectedDate = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date)
            }
            step = .category
        case .category:
            category = TaskCategory(rawValue: chip.value) ?? .personal
            step = .confirm
        case .confirm:
            if chip.value == "edit" {
                step = .title  // restart
            }
            // "create" and "cancel" handled by ChatView
        default:
            break
        }
    }

    func setTitle(_ text: String) {
        title = text
        step = .priority
    }

    func start() {
        step = .title
        title = nil
        priority = .medium
        selectedDate = nil
        timeOfDay = nil
        category = .personal
    }

    func reset() {
        step = .idle
        title = nil
        priority = .medium
        selectedDate = nil
        timeOfDay = nil
        category = .personal
    }

    /// Build the final TaskItem
    func buildTask() -> TaskItem {
        TaskItem(
            title: title ?? "Untitled Task",
            category: category,
            priority: priority,
            date: selectedDate ?? Date(),
            icon: category.icon,
            notes: ""
        )
    }
}
