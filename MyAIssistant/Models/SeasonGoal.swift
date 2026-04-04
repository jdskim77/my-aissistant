import Foundation
import SwiftData

/// A 4-week focus goal for one life dimension. The user picks one dimension
/// to intentionally invest in for 28 days. Nudges are weighted toward this dimension.
@Model
final class SeasonGoal {
    var id: String
    var dimensionRaw: String
    var startDate: Date
    var endDate: Date
    /// User's free-text intention, e.g. "Get back to running 3x/week"
    var intention: String
    var completedAt: Date?

    @Transient
    var dimension: LifeDimension {
        get { LifeDimension(rawValue: dimensionRaw) ?? .physical }
        set { dimensionRaw = newValue.rawValue }
    }

    @Transient
    var isActive: Bool {
        guard completedAt == nil else { return false }
        // Active through the entirety of the final day
        let endOfFinalDay = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        return Date() < endOfFinalDay
    }

    @Transient
    var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0)
    }

    @Transient
    var progress: Double {
        let total = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 28
        let effectiveEnd = completedAt ?? Date()
        let elapsed = Calendar.current.dateComponents([.day], from: startDate, to: effectiveEnd).day ?? 0
        return min(1.0, Double(elapsed) / Double(max(1, total)))
    }

    init(dimension: LifeDimension, intention: String = "") {
        self.id = UUID().uuidString
        self.dimensionRaw = dimension.rawValue
        self.startDate = Calendar.current.startOfDay(for: Date())
        self.endDate = Calendar.current.date(byAdding: .day, value: 28, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        self.intention = intention
    }
}
