import Foundation

/// A transient "a task just completed" signal that the Balance Pulse card
/// can react to. Published from `TaskManager.toggleCompletion` via
/// `BalancePulseBus` so every completion path (Home list, Focus timer,
/// Schedule, Watch sync) gets the same visible Compass movement.
///
/// The UUID `token` is the change trigger — ignoring value identity means a
/// user who completes two tasks on the same dimension in a row gets two
/// distinct pulses instead of one swallowed by SwiftUI's equality check.
///
/// `createdAt` lets the subscriber ignore stale pulses (e.g. a pulse fired
/// while the user was on another tab shouldn't replay when they return to
/// Home seconds later).
struct BalancePulse: Equatable, Sendable {
    let dimension: LifeDimension
    /// Points contribution to the dimension. For multi-dim tasks this is the
    /// per-dimension split share, matching how BalanceManager computes the
    /// real activity score.
    let points: Int
    let token: UUID
    let createdAt: Date

    init(dimension: LifeDimension, points: Int, token: UUID = UUID(), createdAt: Date = Date()) {
        self.dimension = dimension
        self.points = points
        self.token = token
        self.createdAt = createdAt
    }

    /// True if the pulse is older than the given window — used by the Balance
    /// Pulse card to skip stale pulses when the view reappears (tab switch).
    func isStale(now: Date = Date(), window: TimeInterval = 3) -> Bool {
        now.timeIntervalSince(createdAt) > window
    }
}
