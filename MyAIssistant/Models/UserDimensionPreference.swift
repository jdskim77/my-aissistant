import Foundation
import SwiftData

/// Tracks the user's learned dimension preference for a specific activity keyword.
/// When a user overrides the AI's dimension suggestion, we record their choice so
/// future suggestions match their intent (e.g., "yoga" → Spiritual for this user).
@Model
final class UserDimensionPreference {
    /// Lowercased activity keyword (e.g., "yoga", "journaling", "cooking")
    var keyword: String
    /// The dimension the user most often assigns to this keyword
    var dimensionRaw: String
    /// Number of times this keyword was tagged with this dimension
    var confirmCount: Int
    /// Total times this keyword was tagged with any dimension
    var totalCount: Int
    var lastUpdated: Date

    @Transient
    var dimension: LifeDimension {
        get { LifeDimension(rawValue: dimensionRaw) ?? .practical }
        set { dimensionRaw = newValue.rawValue }
    }

    @Transient
    var confidence: Double {
        guard totalCount > 0 else { return 0 }
        return Double(confirmCount) / Double(totalCount)
    }

    init(keyword: String, dimension: LifeDimension) {
        self.keyword = keyword.lowercased()
        self.dimensionRaw = dimension.rawValue
        self.confirmCount = 1
        self.totalCount = 1
        self.lastUpdated = Date()
    }
}
