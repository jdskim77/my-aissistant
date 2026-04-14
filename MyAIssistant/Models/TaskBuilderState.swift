import Foundation

enum TaskBuilderStep: String {
    case idle
    case title       // waiting for text input
    case priority    // show priority chips
    case date        // show date chips
    case time        // show time chips
    case category    // show category chips
    case dimension   // show life dimension chips
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
    var selectedDimensions: Set<LifeDimension> = []
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
        case .dimension:
            return [
                TaskBuilderChip(label: "Physical", icon: "🏃‍♂️", value: "Physical"),
                TaskBuilderChip(label: "Mental", icon: "🧠", value: "Mental"),
                TaskBuilderChip(label: "Emotional", icon: "❤️", value: "Emotional"),
                TaskBuilderChip(label: "Spiritual", icon: "✨", value: "Spiritual"),
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
        case .dimension:
            if !selectedDimensions.isEmpty {
                let labels = selectedDimensions.map(\.label).joined(separator: " + ")
                return "\(labels) selected. Tap more or tap Done."
            }
            return "Which parts of your life does this serve? (pick up to 3)"
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
        let dimStr = selectedDimensions.isEmpty ? "🧭 No dimension" : "🧭 " + selectedDimensions.map(\.label).joined(separator: " + ")
        return "Here's your task:\n\n📋 \(title ?? "Untitled")\n📅 \(dateStr)\(timeStr)\n⚡ \(priority.rawValue) priority\n🏷 \(category.rawValue)\n\(dimStr)\n\nLook good?"
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
            // Auto-suggest dimension from category (user can override on next step)
            selectedDimensions.removeAll()
            switch category {
            case .health: selectedDimensions.insert(.physical)
            case .work: selectedDimensions.insert(.mental)
            default: break
            }
            step = .dimension
        case .dimension:
            if chip.value == "done" {
                // Finish dimension selection — move to confirm
                step = .confirm
            } else if let dim = LifeDimension(rawValue: chip.value) {
                // Toggle dimension on/off (max 3)
                if selectedDimensions.contains(dim) {
                    selectedDimensions.remove(dim)
                } else if selectedDimensions.count < 3 {
                    selectedDimensions.insert(dim)
                }
                // Don't advance step — let user pick more or tap Done
            }
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

    /// Attempt to parse free-text date input like "today", "tomorrow", "friday", "april 15".
    /// Returns true if parsing succeeded and the step advanced.
    func setDateFromText(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        var parsed: Date?

        switch lower {
        case "today", "now":
            parsed = today
        case "tomorrow", "tmrw", "tmr":
            parsed = cal.date(byAdding: .day, value: 1, to: today)
        case "this week":
            parsed = cal.date(byAdding: .day, value: 3, to: today)
        default:
            // Try weekday names: "monday", "friday", "sat", etc.
            let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            let shortWeekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
            if let idx = weekdays.firstIndex(of: lower) ?? shortWeekdays.firstIndex(of: lower) {
                let targetWeekday = idx + 1 // Calendar weekday is 1-based
                let currentWeekday = cal.component(.weekday, from: today)
                var daysAhead = targetWeekday - currentWeekday
                if daysAhead <= 0 { daysAhead += 7 }
                parsed = cal.date(byAdding: .day, value: daysAhead, to: today)
            }

            // Try natural date parsing as fallback
            if parsed == nil {
                let formatter = DateFormatter()
                formatter.locale = Locale.current
                for format in ["MMM d", "MMMM d", "MM/dd", "M/d"] {
                    formatter.dateFormat = format
                    if let d = formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        // Set to current year
                        var components = cal.dateComponents([.month, .day], from: d)
                        components.year = cal.component(.year, from: today)
                        if let result = cal.date(from: components) {
                            parsed = result < today ? cal.date(byAdding: .year, value: 1, to: result) : result
                        }
                        break
                    }
                }
            }
        }

        guard let date = parsed else { return false }
        selectedDate = date
        step = .time
        return true
    }

    /// Attempt to parse free-text time input like "11:08pm", "9am", "2:30 PM", "14:00".
    /// Returns true if parsing succeeded and the step advanced.
    func setTimeFromText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let formats = ["h:mma", "h:mm a", "ha", "h a", "HH:mm", "H:mm", "hmma", "hmm a"]
        var parsedTime: Date?
        for format in formats {
            formatter.dateFormat = format
            if let d = formatter.date(from: trimmed) {
                parsedTime = d
                break
            }
        }

        guard let time = parsedTime, let base = selectedDate else { return false }

        let cal = Calendar.current
        let hour = cal.component(.hour, from: time)
        let minute = cal.component(.minute, from: time)
        selectedDate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: base)
        timeOfDay = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"
        step = .category
        return true
    }

    func start() {
        step = .title
        title = nil
        priority = .medium
        selectedDate = nil
        timeOfDay = nil
        category = .personal
        selectedDimensions = []
    }

    func reset() {
        step = .idle
        title = nil
        priority = .medium
        selectedDate = nil
        timeOfDay = nil
        category = .personal
        selectedDimensions = []
    }

    /// Build the final TaskItem
    func buildTask() -> TaskItem {
        let task = TaskItem(
            title: title ?? "Untitled Task",
            category: category,
            priority: priority,
            date: selectedDate ?? Date(),
            icon: category.icon,
            notes: ""
        )
        task.dimensions = Array(selectedDimensions)
        return task
    }
}
