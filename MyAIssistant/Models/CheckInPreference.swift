import Foundation
import SwiftData

@Model
final class CheckInPreference {
    var id: String
    var windowRaw: String
    var isEnabled: Bool
    var customHour: Int
    var customMinute: Int
    var customTitle: String?
    var isSystemGenerated: Bool
    var createdAt: Date

    @Transient
    var checkInTime: CheckInTime? {
        CheckInTime(rawValue: windowRaw)
    }

    var displayTitle: String {
        customTitle ?? checkInTime?.title ?? windowRaw
    }

    var displayIcon: String {
        checkInTime?.icon ?? "⏰"
    }

    var displayColor: String {
        switch checkInTime {
        case .morning: return "FF9500"
        case .midday: return "34C759"
        case .afternoon: return "007AFF"
        case .night: return "5856D6"
        case nil: return "8E8E93"
        }
    }

    var scheduledTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var components = DateComponents()
        components.hour = customHour
        components.minute = customMinute
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }

    init(
        id: String = UUID().uuidString,
        windowRaw: String,
        isEnabled: Bool = true,
        customHour: Int,
        customMinute: Int = 0,
        customTitle: String? = nil,
        isSystemGenerated: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.windowRaw = windowRaw
        self.isEnabled = isEnabled
        self.customHour = customHour
        self.customMinute = customMinute
        self.customTitle = customTitle
        self.isSystemGenerated = isSystemGenerated
        self.createdAt = createdAt
    }

    static func defaultPreferences() -> [CheckInPreference] {
        CheckInTime.allCases.map { time in
            CheckInPreference(
                windowRaw: time.rawValue,
                customHour: time.hour,
                customMinute: 0,
                isSystemGenerated: true
            )
        }
    }
}
