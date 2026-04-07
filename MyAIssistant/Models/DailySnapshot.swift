import Foundation
import SwiftData

@Model
final class DailySnapshot {
    var id: String = UUID().uuidString
    var date: Date = Date()
    var tasksTotal: Int = 0
    var tasksCompleted: Int = 0
    var checkInsCompleted: Int = 0
    var checkInsTotal: Int = 4
    var averageMood: Double?
    var streakCount: Int = 0

    init(
        id: String = UUID().uuidString,
        date: Date,
        tasksTotal: Int = 0,
        tasksCompleted: Int = 0,
        checkInsCompleted: Int = 0,
        checkInsTotal: Int = 4,
        averageMood: Double? = nil,
        streakCount: Int = 0
    ) {
        self.id = id
        self.date = date
        self.tasksTotal = tasksTotal
        self.tasksCompleted = tasksCompleted
        self.checkInsCompleted = checkInsCompleted
        self.checkInsTotal = checkInsTotal
        self.averageMood = averageMood
        self.streakCount = streakCount
    }
}
