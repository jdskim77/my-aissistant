import Foundation
import SwiftData

/// Records the user's check-in satisfaction ratings per life dimension.
/// Each check-in stores a 1-5 rating for each scored dimension, plus an optional
/// "best energy" dimension and energy level. Multiple check-ins per day are supported
/// (morning, midday, afternoon, evening).
@Model
final class DailyBalanceCheckIn {
    var id: String = UUID().uuidString
    var date: Date = Date()

    /// Which dimension received the user's best energy today (legacy / evening summary)
    var dimensionRaw: String = "practical"

    /// Daily energy level: -3 (drained) to +3 (energized). Nil if not rated.
    var energyRating: Int?

    /// Per-dimension satisfaction ratings (1-5). Nil if not rated.
    var physicalSatisfaction: Int?
    var mentalSatisfaction: Int?
    var emotionalSatisfaction: Int?
    var spiritualSatisfaction: Int?

    @Transient
    var dimension: LifeDimension {
        get { LifeDimension(rawValue: dimensionRaw) ?? .practical }
        set { dimensionRaw = newValue.rawValue }
    }

    init(
        dimension: LifeDimension = .practical,
        energyRating: Int? = nil,
        physicalSatisfaction: Int? = nil,
        mentalSatisfaction: Int? = nil,
        emotionalSatisfaction: Int? = nil,
        spiritualSatisfaction: Int? = nil,
        date: Date = Date()
    ) {
        self.id = UUID().uuidString
        self.date = Calendar.current.startOfDay(for: date)
        self.dimensionRaw = dimension.rawValue
        self.energyRating = energyRating
        self.physicalSatisfaction = physicalSatisfaction
        self.mentalSatisfaction = mentalSatisfaction
        self.emotionalSatisfaction = emotionalSatisfaction
        self.spiritualSatisfaction = spiritualSatisfaction
    }

    /// Get satisfaction rating for a specific dimension.
    func satisfaction(for dimension: LifeDimension) -> Int? {
        switch dimension {
        case .physical: return physicalSatisfaction
        case .mental: return mentalSatisfaction
        case .emotional: return emotionalSatisfaction
        case .spiritual: return spiritualSatisfaction
        case .practical: return nil
        }
    }

    /// Set satisfaction rating for a specific dimension.
    func setSatisfaction(_ rating: Int, for dimension: LifeDimension) {
        switch dimension {
        case .physical: physicalSatisfaction = rating
        case .mental: mentalSatisfaction = rating
        case .emotional: emotionalSatisfaction = rating
        case .spiritual: spiritualSatisfaction = rating
        case .practical: break
        }
    }
}
