import Foundation
import SwiftData

@Model
final class CheckInBehavior {
    var id: String
    var windowRaw: String
    var completionRate: Double
    var averageCompletionHour: Int
    var averageCompletionMinute: Int
    var consecutiveSkips: Int
    var totalCompleted: Int
    var totalOpportunities: Int
    var lastCompletedDate: Date?
    var lastCalculatedDate: Date

    @Transient
    var checkInTime: CheckInTime? {
        CheckInTime(rawValue: windowRaw)
    }

    var completionPercentage: Int {
        Int((completionRate * 100).rounded())
    }

    var averageTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var components = DateComponents()
        components.hour = averageCompletionHour
        components.minute = averageCompletionMinute
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }

    init(
        id: String = UUID().uuidString,
        windowRaw: String,
        completionRate: Double = 0,
        averageCompletionHour: Int = 0,
        averageCompletionMinute: Int = 0,
        consecutiveSkips: Int = 0,
        totalCompleted: Int = 0,
        totalOpportunities: Int = 0,
        lastCompletedDate: Date? = nil,
        lastCalculatedDate: Date = Date()
    ) {
        self.id = id
        self.windowRaw = windowRaw
        self.completionRate = completionRate
        self.averageCompletionHour = averageCompletionHour
        self.averageCompletionMinute = averageCompletionMinute
        self.consecutiveSkips = consecutiveSkips
        self.totalCompleted = totalCompleted
        self.totalOpportunities = totalOpportunities
        self.lastCompletedDate = lastCompletedDate
        self.lastCalculatedDate = lastCalculatedDate
    }
}
