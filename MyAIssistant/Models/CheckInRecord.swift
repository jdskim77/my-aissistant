import Foundation
import SwiftData

@Model
final class CheckInRecord {
    var id: String = UUID().uuidString
    var timeSlotRaw: String = "morning"
    var date: Date = Date()
    var completed: Bool = false
    var mood: Int?
    var energyLevel: Int?
    var notes: String?
    var aiSummary: String?

    @Transient
    var timeSlot: CheckInTime {
        get { CheckInTime(rawValue: timeSlotRaw) ?? .morning }
        set { timeSlotRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        timeSlot: CheckInTime,
        date: Date = Date(),
        completed: Bool = false,
        mood: Int? = nil,
        energyLevel: Int? = nil,
        notes: String? = nil,
        aiSummary: String? = nil
    ) {
        self.id = id
        self.timeSlotRaw = timeSlot.rawValue
        self.date = date
        self.completed = completed
        self.mood = mood
        self.energyLevel = energyLevel
        self.notes = notes
        self.aiSummary = aiSummary
    }
}
