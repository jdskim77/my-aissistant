import SwiftUI

enum CheckInTime: String, CaseIterable, Identifiable {
    case morning = "Morning"
    case midday = "Midday"
    case afternoon = "Afternoon"
    case night = "Night"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .morning:   return "sunrise.fill"
        case .midday:    return "sun.max.fill"
        case .afternoon: return "sunset.fill"
        case .night:     return "moon.stars.fill"
        }
    }

    var icon: String {
        switch self {
        case .morning: return "🌅"
        case .midday: return "☀️"
        case .afternoon: return "🌆"
        case .night: return "🌙"
        }
    }

    var hour: Int {
        switch self {
        case .morning: return 8
        case .midday: return 13
        case .afternoon: return 18
        case .night: return 22
        }
    }

    var timeLabel: String {
        switch self {
        case .morning: return "8:00 AM"
        case .midday: return "1:00 PM"
        case .afternoon: return "6:00 PM"
        case .night: return "10:00 PM"
        }
    }

    var title: String {
        switch self {
        case .morning: return "Morning Brief"
        case .midday: return "Midday Check-in"
        case .afternoon: return "Late Afternoon"
        case .night: return "Night Wind-down"
        }
    }

    var color: Color {
        switch self {
        case .morning: return Color(hex: "FF9500")
        case .midday: return Color(hex: "34C759")
        case .afternoon: return Color(hex: "007AFF")
        case .night: return Color(hex: "5856D6")
        }
    }

    var greeting: String {
        switch self {
        case .morning: return "Good morning! Let's make today count."
        case .midday: return "Halfway through the day — you're doing great!"
        case .afternoon: return "Wrapping up the day. Let's see how you did."
        case .night: return "Time to wind down. Here's your day in review."
        }
    }

    var motivationTip: String {
        switch self {
        case .morning: return "Start with your hardest task — you have the most energy now."
        case .midday: return "Take a 5-minute break. You'll come back sharper."
        case .afternoon: return "Review tomorrow's priorities before you log off."
        case .night: return "Rest is productive too. You've earned it."
        }
    }

    /// The slot the user is currently in. Boundaries match how humans name
    /// times of day (morning through noon, midday through late afternoon,
    /// afternoon through night, night after 9pm). NOTE: these boundaries
    /// intentionally do NOT align with each slot's `.hour` anchor — the anchor
    /// is used for notification scheduling and record anchoring, while these
    /// boundaries drive user-facing labels. Don't "simplify" them together.
    static func current() -> CheckInTime {
        return slot(forHour: Calendar.current.component(.hour, from: Date()))
    }

    /// Pure function form of `current()` — testable and reusable.
    /// Single source of truth for slot labels across iOS, Watch, and widgets.
    static func slot(forHour hour: Int) -> CheckInTime {
        if hour < 12 { return .morning }    // 00:00–11:59 (early risers see Morning)
        if hour < 17 { return .midday }     // 12:00–16:59
        if hour < 21 { return .afternoon }  // 17:00–20:59
        return .night                        // 21:00–23:59
    }

    /// The next slot to prompt for. Same boundaries as `current()` — historical
    /// callers (home-screen sheet, notification scheduling) just want "which
    /// check-in should I open right now?", which is the current slot.
    static func next() -> CheckInTime {
        return current()
    }

}
