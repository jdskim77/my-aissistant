import Foundation
import SwiftData

@Model
final class FocusSession {
    var id: String = UUID().uuidString
    var taskID: String?
    var taskTitle: String = "Focus Session"
    var startedAt: Date = Date()
    var endedAt: Date?
    var workDuration: Int = 1500          // seconds per work interval
    var breakDuration: Int = 300          // seconds per break interval
    var intervalsCompleted: Int = 0
    var intervalsTarget: Int = 4
    var totalFocusSeconds: Int = 0        // actual accumulated focus time
    var completed: Bool = false           // did user finish all intervals?

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
