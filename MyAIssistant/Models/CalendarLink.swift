import Foundation
import SwiftData

@Model
final class CalendarLink {
    var id: String = UUID().uuidString
    var source: String = "apple"
    var calendarID: String = ""
    var name: String = ""
    var color: String = "#2D5016"
    var enabled: Bool = true
    var lastSynced: Date?
    var createdAt: Date = Date()

    // MARK: - Computed source accessor

    @Transient
    var calendarSource: CalendarSource {
        get { CalendarSource(rawValue: source) ?? .apple }
        set { source = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        source: CalendarSource,
        calendarID: String,
        name: String,
        color: String = "#2D5016",
        enabled: Bool = true
    ) {
        self.id = id
        self.source = source.rawValue
        self.calendarID = calendarID
        self.name = name
        self.color = color
        self.enabled = enabled
        self.lastSynced = nil
        self.createdAt = Date()
    }
}

// MARK: - Calendar Source

enum CalendarSource: String, CaseIterable, Identifiable {
    case apple
    case google
    case reminders

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple Calendar"
        case .google: return "Google Calendar"
        case .reminders: return "Reminders"
        }
    }

    var icon: String {
        switch self {
        case .apple: return "calendar"
        case .google: return "globe"
        case .reminders: return "checklist"
        }
    }
}
