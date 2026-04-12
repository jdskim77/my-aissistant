import Foundation
import Observation
import SwiftData

@Observable @MainActor
final class HabitManager {
    private let modelContext: ModelContext

    /// Set by the app to enable automatic notification re-scheduling on habit changes.
    var notificationManager: NotificationManager?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Toggle Completion

    func toggleCompletion(_ habit: HabitItem, for date: Date) {
        habit.toggleCompletion(for: date)
        modelContext.safeSave()
    }

    // MARK: - Create / Update

    func save(_ habit: HabitItem) {
        if habit.modelContext == nil {
            modelContext.insert(habit)
        }
        modelContext.safeSave()
        rescheduleHabitReminders()
    }

    // MARK: - Delete

    func delete(_ habit: HabitItem) {
        let habitID = habit.id
        modelContext.delete(habit)
        modelContext.safeSave()
        notificationManager?.cancelHabitReminder(habitID: habitID)
    }

    // MARK: - Archive

    func archive(_ habit: HabitItem) {
        habit.archivedAt = Date()
        modelContext.safeSave()
        notificationManager?.cancelHabitReminder(habitID: habit.id)
    }

    // MARK: - Notification Re-scheduling

    /// Re-schedule all active habit reminders. Call after any habit is created or edited.
    func rescheduleHabitReminders() {
        guard let nm = notificationManager else { return }
        var descriptor = FetchDescriptor<HabitItem>(
            predicate: #Predicate { $0.archivedAt == nil }
        )
        descriptor.fetchLimit = 50
        let activeHabits = (try? modelContext.fetch(descriptor)) ?? []
        nm.scheduleHabitReminders(activeHabits)
    }
}
