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
    /// True when this record was completed via a notification mood action
    /// (Feature 1: 10-second quick check-in) rather than the full in-app
    /// flow. Additive property with a default, so it's a lightweight
    /// SwiftData migration — no SchemaV2 needed (see SchemaVersioning.swift).
    var isQuickCheckIn: Bool = false

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
        aiSummary: String? = nil,
        isQuickCheckIn: Bool = false
    ) {
        self.id = id
        self.timeSlotRaw = timeSlot.rawValue
        self.date = date
        self.completed = completed
        self.mood = mood
        self.energyLevel = energyLevel
        self.notes = notes
        self.aiSummary = aiSummary
        self.isQuickCheckIn = isQuickCheckIn
    }
}
