import Foundation

/// Pure ring-completion and "remaining items" logic for the Today/Home
/// hero card, factored out of `HomeView` so it's unit-testable without
/// SwiftData/ModelContext scaffolding (Impeccable Screens audit P2:
/// "extract to a pure function if needed").
enum HomeProgressCalc {
    /// Blended day-completion fraction (0...1). Mirrors the ring's center
    /// percentage. Tasks only contribute units when `totalTasks > 0` —
    /// a day with zero scheduled tasks is NOT read as "0 of 0 tasks done"
    /// (which would be a phantom denominator); the ring reflects
    /// check-ins alone in that case (Impeccable Screens audit: "ring
    /// excludes 0/0 tasks").
    static func dayCompletionFraction(
        completedTasks: Int,
        totalTasks: Int,
        completedCheckIns: Int,
        totalCheckInSlots: Int = 4
    ) -> Double {
        let taskUnits = max(0, totalTasks)
        let checkInUnits = max(0, totalCheckInSlots)
        let totalUnits = taskUnits + checkInUnits
        guard totalUnits > 0 else { return 0 }
        let doneUnits = completedTasks + completedCheckIns
        return min(1.0, Double(doneUnits) / Double(totalUnits))
    }

    /// True when a bare "0%" would misleadingly read as "you've done
    /// nothing" — i.e. the fraction is exactly 0 AND it's evening or
    /// later. Swaps to remaining-items copy in that case (Impeccable
    /// Screens audit: night remaining-items text after 6pm).
    static func shouldShowRemainingItemsInsteadOfPercent(
        dayCompletionFraction: Double,
        hour: Int
    ) -> Bool {
        guard dayCompletionFraction == 0 else { return false }
        return hour >= 18
    }

    /// "<n> tasks, <n> check-ins left" copy, or "all clear" when both are
    /// zero.
    static func remainingItemsText(
        completedTasks: Int,
        totalTasks: Int,
        completedCheckIns: Int,
        totalCheckInSlots: Int = 4
    ) -> String {
        let remainingTasks = max(0, totalTasks - completedTasks)
        let remainingCheckIns = max(0, totalCheckInSlots - completedCheckIns)
        if remainingTasks == 0 && remainingCheckIns == 0 {
            return "all clear"
        }
        var parts: [String] = []
        if remainingTasks > 0 {
            parts.append("\(remainingTasks) task\(remainingTasks == 1 ? "" : "s")")
        }
        if remainingCheckIns > 0 {
            parts.append("\(remainingCheckIns) check-in\(remainingCheckIns == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ") + " left"
    }
}
