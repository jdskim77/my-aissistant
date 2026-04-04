import Foundation
import SwiftData

/// Tracks a recurring activity pattern learned from the user's completed tasks.
/// Used by Smart Activity Recall to suggest unlogged activities during the evening check-in.
@Model
final class ActivityPattern {
    var id: String

    /// Normalized activity name (lowercased, e.g., "yoga", "morning run")
    var activityName: String

    /// The dimension the user typically tags this activity with
    var dimensionRaw: String

    /// Most common duration in minutes (e.g., 30 for a 30-min yoga session)
    var typicalDurationMinutes: Int

    /// Days of the week this activity typically occurs (1=Sun, 2=Mon, ... 7=Sat)
    var weekdayPatternRaw: String // Comma-separated ints: "2,4,6" for Mon/Wed/Fri

    /// How many times per week this activity typically occurs
    var weeklyFrequency: Int

    /// Number of times the recall suggestion was shown for this pattern
    var totalSuggested: Int

    /// Number of times the user confirmed "yes I did this"
    var totalAccepted: Int

    /// Consecutive times the user dismissed the suggestion (resets on accept)
    var consecutiveDismissals: Int

    /// Last time this pattern was suggested in a recall prompt
    var lastSuggested: Date?

    /// Last time the user confirmed doing this activity
    var lastConfirmed: Date?

    /// When this pattern was first detected
    var createdAt: Date

    // MARK: - Transient Accessors

    @Transient
    var dimension: LifeDimension {
        get { LifeDimension(rawValue: dimensionRaw) ?? .physical }
        set { dimensionRaw = newValue.rawValue }
    }

    @Transient
    var weekdayPattern: [Int] {
        get {
            weekdayPatternRaw.split(separator: ",").compactMap { Int($0) }
        }
        set {
            weekdayPatternRaw = newValue.map(String.init).joined(separator: ",")
        }
    }

    @Transient
    var acceptanceRate: Double {
        guard totalSuggested > 0 else { return 0.5 } // default for new patterns
        return Double(totalAccepted) / Double(totalSuggested)
    }

    /// Whether this pattern is suppressed (3+ consecutive dismissals)
    @Transient
    var isSuppressed: Bool {
        consecutiveDismissals >= 3
    }

    /// Confidence score for suggesting this activity today (0.0 - 1.0)
    func confidenceForToday() -> Double {
        guard !isSuppressed else { return 0 }

        let today = Calendar.current.component(.weekday, from: Date())

        // Base frequency: how often per week (3/week = 0.43, 5/week = 0.71, 7/week = 1.0)
        let baseFrequency = min(1.0, Double(weeklyFrequency) / 7.0)

        // Day match: 1.5x boost if today matches a pattern day, 0.5x if not
        let dayMatch: Double = weekdayPattern.contains(today) ? 1.5 : 0.5

        // Recency: 1.0 if confirmed within 2 weeks, decays 10% per week after
        let recencyBoost: Double
        if let lastConfirmed {
            let weeksSince = Double(Calendar.current.dateComponents([.day], from: lastConfirmed, to: Date()).day ?? 0) / 7.0
            recencyBoost = weeksSince <= 2 ? 1.0 : max(0.3, 1.0 - (weeksSince - 2) * 0.1)
        } else {
            recencyBoost = 0.5
        }

        // Acceptance rate (floor at 0.3 for new patterns)
        let acceptance = max(0.3, acceptanceRate)

        return min(1.0, baseFrequency * dayMatch * recencyBoost * acceptance)
    }

    // MARK: - Init

    init(
        activityName: String,
        dimension: LifeDimension,
        typicalDurationMinutes: Int = 30,
        weekdayPattern: [Int] = [],
        weeklyFrequency: Int = 3
    ) {
        self.id = UUID().uuidString
        self.activityName = activityName.lowercased()
        self.dimensionRaw = dimension.rawValue
        self.typicalDurationMinutes = typicalDurationMinutes
        self.weekdayPatternRaw = weekdayPattern.map(String.init).joined(separator: ",")
        self.weeklyFrequency = weeklyFrequency
        self.totalSuggested = 0
        self.totalAccepted = 0
        self.consecutiveDismissals = 0
        self.createdAt = Date()
    }
}
