import Foundation
import SwiftData

/// CRUD for the user's 4-week season goal. Extracted verbatim from
/// `BalanceManager`, which keeps the public API and delegates here.
/// `seasonGoalProgress()` stays on `BalanceManager` because it needs the
/// weekly score from the scoring path.
@MainActor
struct SeasonGoalStore {
    let modelContext: ModelContext

    func activeSeasonGoal() -> SeasonGoal? {
        // Use startOfDay to include the entire final day (matches SeasonGoal.isActive logic)
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<SeasonGoal>(
            predicate: #Predicate { $0.completedAt == nil && $0.endDate >= today },
            sortBy: [SortDescriptor(\SeasonGoal.startDate, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first
    }

    func startSeasonGoal(dimension: LifeDimension, intention: String) {
        if let existing = activeSeasonGoal() { existing.completedAt = Date() }
        let goal = SeasonGoal(dimension: dimension, intention: intention)
        modelContext.insert(goal)
        modelContext.safeSave()
    }

    func completeSeasonGoal() {
        if let goal = activeSeasonGoal() {
            goal.completedAt = Date()
            modelContext.safeSave()
        }
    }
}
