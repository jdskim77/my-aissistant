import Foundation
import SwiftData

@Model
final class DailySnapshot {
    var id: String
    var date: Date
    var tasksTotal: Int
    var tasksCompleted: Int
    var checkInsCompleted: Int
    var checkInsTotal: Int
    var averageMood: Double?
    var streakCount: Int

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
