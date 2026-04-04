import Foundation
import Observation
import SwiftData

@Observable @MainActor
final class HabitManager {
    private let modelContext: ModelContext

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
    }

    // MARK: - Delete

    func delete(_ habit: HabitItem) {
        modelContext.delete(habit)
        modelContext.safeSave()
    }
}
