import Foundation
import Observation
import SwiftData

@Observable @MainActor
final class HabitManager {
    private let modelContext: ModelContext

    /// Set by the app to enable automatic notification re-scheduling on habit changes.
    var notificationManager: NotificationManager?
    /// Invalidated + drives the Balance Pulse animation when a dimension-
    /// tagged habit flips to complete. Wired in MyAIssistantApp alongside
    /// the TaskManager hookup.
    var balanceManager: BalanceManager?
    var balancePulseBus: BalancePulseBus?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Per-habit throttle for `toggleCompletion`. Rapid successive taps (e.g.
    /// user double-tapping a checkbox while the spring animation is playing)
    /// would otherwise flip set membership back-and-forth, producing 0–2
    /// pulses unpredictably. @ObservationIgnored so cache writes don't
    /// trigger view re-renders.
    @ObservationIgnored private var lastToggleAt: [String: Date] = [:]
    private static let toggleThrottle: TimeInterval = 0.25

    // MARK: - Toggle Completion

    func toggleCompletion(_ habit: HabitItem, for date: Date) {
        let now = Date()
        if let last = lastToggleAt[habit.id], now.timeIntervalSince(last) < Self.toggleThrottle {
            return
        }
        lastToggleAt[habit.id] = now

        habit.toggleCompletion(for: date)
        modelContext.safeSave()

        // Completion → Compass feedback loop. Only celebrate forward motion;
        // unchecking a habit doesn't pulse. We check state AFTER the toggle,
        // so `isCompletedOn == true` here means the flip just completed it.
        guard habit.isCompletedOn(date) else { return }
        publishPulse(for: habit)
    }

    /// Announce a completion that was performed OUTSIDE this manager (Siri,
    /// Widget, Notification action, Shortcut). Validates state, invalidates
    /// the BalanceManager cache, and publishes a pulse — but does NOT
    /// re-toggle, so it's safe to call after the mutation has already landed.
    func announceCompletion(habitID: String) {
        guard let habit = findHabit(byID: habitID) else { return }
        let today = Calendar.current.startOfDay(for: Date())
        guard habit.isCompletedOn(today) else { return }
        publishPulse(for: habit)
    }

    /// Shared pulse-publishing path for both in-manager completion and
    /// external announcements. Cache is only invalidated when the habit
    /// actually contributes to a scored dimension — untagged habit toggles
    /// are score-neutral and the cache doesn't need to be flushed.
    private func publishPulse(for habit: HabitItem) {
        guard let dim = habit.dimensions.primaryScored else { return }
        balanceManager?.invalidateCache()
        let scoredCount = habit.dimensions.filter(\.isScored).count
        let share = splitPoints(total: HabitManager.habitEffortPoints, across: scoredCount)
        balancePulseBus?.publish(BalancePulse(dimension: dim, points: share))
    }

    func findHabit(byID id: String) -> HabitItem? {
        let descriptor = FetchDescriptor<HabitItem>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Per-completion activity points a habit contributes. Kept in sync with
    /// `BalanceManager.activitySignalFromHabits`.
    static let habitEffortPoints: Int = 2

    private func splitPoints(total: Int, across count: Int) -> Int {
        guard count > 0 else { return total }
        let share = Double(total) / Double(count)
        return max(1, Int(share.rounded()))
    }

    // MARK: - Mark Missed

    /// Explicitly mark a habit as missed for a given day. Clears any prior
    /// completion for the same day (invariant enforced in the model) and
    /// invalidates the Balance cache so today's consistency/data-weight
    /// scoring reflects the explicit miss.
    func markMissed(_ habit: HabitItem, for date: Date) {
        habit.markMissed(for: date)
        modelContext.safeSave()
        if habit.dimensions.primaryScored != nil {
            balanceManager?.invalidateCache()
        }
    }

    /// Clear the "missed" flag for a day, returning the habit to pending.
    /// Invalidates Balance cache because the removal can restore `hasRealData`
    /// semantics for scored dimensions.
    func unmarkMissed(_ habit: HabitItem, for date: Date) {
        habit.unmarkMissed(for: date)
        modelContext.safeSave()
        if habit.dimensions.primaryScored != nil {
            balanceManager?.invalidateCache()
        }
    }

    // MARK: - Create / Update

    func save(_ habit: HabitItem) {
        if habit.modelContext == nil {
            modelContext.insert(habit)
        }
        modelContext.safeSave()
        // Re-tagging a dimension re-attributes every past completion this
        // week, so the Compass must re-flow immediately rather than waiting
        // for the 30s cache TTL.
        balanceManager?.invalidateCache()
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
