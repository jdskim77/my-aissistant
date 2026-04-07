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

    static func current() -> CheckInTime {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 11 { return .morning }
        if hour < 16 { return .midday }
        if hour < 20 { return .afternoon }
        return .night
    }

    static func next() -> CheckInTime {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 8 { return .morning }
        if hour < 13 { return .midday }
        if hour < 18 { return .afternoon }
        if hour < 22 { return .night }
        return .morning // next day
    }

}
