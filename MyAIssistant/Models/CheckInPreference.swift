import Foundation
import SwiftData

@Model
final class CheckInPreference {
    var id: String = UUID().uuidString
    var windowRaw: String = ""
    var isEnabled: Bool = true
    var customHour: Int = 8
    var customMinute: Int = 0
    var customTitle: String?
    var isSystemGenerated: Bool = true
    var createdAt: Date = Date()

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

    var scheduledTimeString: String {
        var components = DateComponents()
        components.hour = customHour
        components.minute = customMinute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
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
