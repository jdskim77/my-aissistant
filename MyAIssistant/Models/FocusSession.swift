import Foundation
import SwiftData

@Model
final class FocusSession {
    var id: String
    var taskID: String?
    var taskTitle: String
    var startedAt: Date
    var endedAt: Date?
    var workDuration: Int          // seconds per work interval
    var breakDuration: Int         // seconds per break interval
    var intervalsCompleted: Int
    var intervalsTarget: Int
    var totalFocusSeconds: Int     // actual accumulated focus time
    var completed: Bool            // did user finish all intervals?

    init(
        id: String = UUID().uuidString,
        taskID: String? = nil,
        taskTitle: String = "Focus Session",
        workDuration: Int = 25 * 60,
        breakDuration: Int = 5 * 60,
        intervalsTarget: Int = 4
    ) {
        self.id = id
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.startedAt = Date()
        self.endedAt = nil
        self.workDuration = workDuration
        self.breakDuration = breakDuration
        self.intervalsCompleted = 0
        self.intervalsTarget = intervalsTarget
        self.totalFocusSeconds = 0
        self.completed = false
    }
}
