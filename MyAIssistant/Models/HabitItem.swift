import Foundation
import SwiftData

@Model
final class HabitItem {
    var id: String
    var title: String
    var icon: String              // emoji
    var colorHex: String          // hex color for display
    var createdAt: Date
    var archivedAt: Date?
    var targetDaysRaw: String     // comma-separated day numbers (1=Sun, 2=Mon, ... 7=Sat), or "daily"
    var reminderHour: Int?        // optional reminder time
    var reminderMinute: Int?

    /// Tracks which dates this habit was completed on.
    /// Stored as comma-separated "yyyy-MM-dd" strings for SwiftData compatibility.
    var completionDatesRaw: String

    // MARK: - Computed

    @Transient
    var isArchived: Bool { archivedAt != nil }

    @Transient
    var targetDays: HabitFrequency {
        get { HabitFrequency(raw: targetDaysRaw) }
        set { targetDaysRaw = newValue.raw }
    }

    @Transient
    var completionDates: Set<String> {
        get {
            guard !completionDatesRaw.isEmpty else { return [] }
            return Set(completionDatesRaw.split(separator: ",").map(String.init))
        }
        set {
            completionDatesRaw = newValue.sorted().joined(separator: ",")
        }
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        icon: String = "✅",
        colorHex: String = "#2D5016",
        targetDays: HabitFrequency = .daily
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.colorHex = colorHex
        self.createdAt = Date()
        self.archivedAt = nil
        self.targetDaysRaw = targetDays.raw
        self.reminderHour = nil
        self.reminderMinute = nil
        self.completionDatesRaw = ""
    }

    // MARK: - Helpers

    private static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func dateKey(for date: Date) -> String {
        Self.dateKeyFormatter.string(from: date)
    }

    func isCompletedOn(_ date: Date) -> Bool {
        completionDates.contains(dateKey(for: date))
    }

    func toggleCompletion(for date: Date) {
        let key = dateKey(for: date)
        var dates = completionDates
        if dates.contains(key) {
            dates.remove(key)
        } else {
            dates.insert(key)
        }
        completionDates = dates
    }

    /// Current streak counting back from today.
    func currentStreak() -> Int {
        let cal = Calendar.current
        var streak = 0
        var checkDate = cal.startOfDay(for: Date())

        // If today isn't completed yet, start from yesterday
        if !isCompletedOn(checkDate) {
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        while isCompletedOn(checkDate) {
            streak += 1
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
        return streak
    }

    /// Completion rate over the last N days.
    func completionRate(days: Int = 30) -> Double {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var completed = 0
        var applicable = 0

        for offset in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            if targetDays.appliesTo(date: date) {
                applicable += 1
                if isCompletedOn(date) { completed += 1 }
            }
        }

        return applicable > 0 ? Double(completed) / Double(applicable) : 0
    }
}

// MARK: - Habit Frequency

enum HabitFrequency: Equatable {
    case daily
    case specificDays(Set<Int>) // 1=Sun ... 7=Sat (Calendar weekday)

    var raw: String {
        switch self {
        case .daily: return "daily"
        case .specificDays(let days):
            return days.sorted().map(String.init).joined(separator: ",")
        }
    }

    init(raw: String) {
        if raw == "daily" {
            self = .daily
        } else {
            let days = Set(raw.split(separator: ",").compactMap { Int($0) })
            self = days.isEmpty ? .daily : .specificDays(days)
        }
    }

    func appliesTo(date: Date) -> Bool {
        switch self {
        case .daily: return true
        case .specificDays(let days):
            let weekday = Calendar.current.component(.weekday, from: date)
            return days.contains(weekday)
        }
    }

    var displayLabel: String {
        switch self {
        case .daily: return "Every day"
        case .specificDays(let days):
            let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            return days.sorted().map { names[$0] }.joined(separator: ", ")
        }
    }
}
