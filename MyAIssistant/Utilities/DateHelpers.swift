import Foundation

extension Calendar {
    /// Safe date addition that falls back to the input date instead of crashing.
    func safeDate(byAdding component: Calendar.Component, value: Int, to date: Date) -> Date {
        self.date(byAdding: component, value: value, to: date) ?? date
    }
}

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var endOfDay: Date {
        Calendar.current.safeDate(byAdding: .day, value: 1, to: startOfDay)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(self)
    }

    func formatted(as format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }

    static func from(month: Int, day: Int, year: Int = 2026, hour: Int = 9) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar.current.date(from: components) ?? Date()
    }
}
