import Foundation

/// Pure timestamp-grouping logic for the chat transcript (Impeccable
/// Screens audit P2: "group consecutive messages and show one time per
/// group"). Kept as free functions over primitives (not SwiftUI, not
/// `ChatMessage` directly) so it's trivially unit-testable without
/// SwiftData/ModelContext scaffolding.
enum MessageGrouping {
    /// Two consecutive messages belong to the same visual group — and so
    /// share one timestamp label — when they're from the same sender and
    /// no more than `windowSeconds` apart. A role change (user → AI or
    /// vice versa) always starts a new group regardless of how close in
    /// time the messages are.
    static func areGrouped(
        sameSender: Bool,
        previousTimestamp: Date,
        currentTimestamp: Date,
        windowSeconds: TimeInterval = 300
    ) -> Bool {
        guard sameSender else { return false }
        // abs() guards against out-of-order timestamps (e.g. clock skew,
        // a backfilled message) so grouping never goes negative/true by
        // accident in the wrong direction.
        return abs(currentTimestamp.timeIntervalSince(previousTimestamp)) <= windowSeconds
    }

    /// Given an ordered (oldest → newest) list of (sender, timestamp)
    /// pairs, returns a parallel array of Bools: `true` at index *i* means
    /// the timestamp should be SHOWN for that message (i.e. it starts a
    /// new group or is the only message in its group); `false` means it's
    /// a continuation of the previous message's group and should be
    /// hidden.
    static func timestampVisibility<Sender: Equatable>(
        for entries: [(sender: Sender, timestamp: Date)],
        windowSeconds: TimeInterval = 300
    ) -> [Bool] {
        guard !entries.isEmpty else { return [] }
        var result = [Bool](repeating: true, count: entries.count)
        for i in 1..<entries.count {
            let prev = entries[i - 1]
            let cur = entries[i]
            let grouped = areGrouped(
                sameSender: prev.sender == cur.sender,
                previousTimestamp: prev.timestamp,
                currentTimestamp: cur.timestamp,
                windowSeconds: windowSeconds
            )
            result[i] = !grouped
        }
        return result
    }
}
