import Foundation
import Observation
import SwiftData

@Observable @MainActor
final class WisdomManager {
    struct Quote: Codable {
        let text: String
        let author: String
        let category: String  // "productivity", "stoic", "wisdom", "mindfulness"
    }

    private let modelContext: ModelContext
    private static var cachedQuotes: [Quote]?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Quote Loading

    static func loadQuotes() -> [Quote] {
        if let cached = cachedQuotes { return cached }
        guard let url = Bundle.main.url(forResource: "DailyWisdom", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let quotes = try? JSONDecoder().decode([Quote].self, from: data) else {
            return []
        }
        cachedQuotes = quotes
        return quotes
    }

    // MARK: - Intelligent Quote Selection (70/20/10)

    /// Returns today's quote using the 70/20/10 blend algorithm:
    /// - 70% of the time: quote from a category matching the user's STRONGEST area (reinforcement)
    /// - 20% of the time: quote from a category matching the user's WEAKEST area (gentle nudge)
    /// - 10% of the time: general wisdom quote
    ///
    /// Modified by context:
    /// - Morning -> bias toward productivity/energizing
    /// - Evening -> bias toward mindfulness/reflective
    /// - Low mood -> stoic/comforting (override)
    /// - High streak (7+) -> stoic/perseverance
    /// - Broken streak -> wisdom (compassionate fresh-start)
    func todayQuote(
        compassScores: [String: Double]? = nil,
        currentMood: Int? = nil,
        streak: Int = 0
    ) -> Quote? {
        let quotes = Self.loadQuotes()
        guard !quotes.isEmpty else { return nil }

        // Use day as seed for deterministic but daily-changing selection
        let daySeed = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0

        // Determine which category pool to draw from
        let targetCategory = selectCategory(
            compassScores: compassScores,
            currentMood: currentMood,
            streak: streak,
            daySeed: daySeed
        )

        // Filter quotes by target category
        let pool = quotes.filter { $0.category == targetCategory }
        guard !pool.isEmpty else {
            // Fallback to any quote
            return quotes[daySeed % quotes.count]
        }

        // Deterministic selection within the pool
        return pool[daySeed % pool.count]
    }

    /// Legacy static method for backward compatibility (used by Watch, Widgets)
    static func todayQuote() -> Quote? {
        let quotes = loadQuotes()
        guard !quotes.isEmpty else { return nil }
        let daySeed = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return quotes[daySeed % quotes.count]
    }

    // MARK: - Category Selection Logic

    /// Maps compass dimension names to quote categories.
    /// Compass dimensions (physical, mental, emotional, spiritual) map to
    /// quote categories (productivity, stoic, mindfulness, wisdom).
    private static let dimensionToCategoryMap: [String: String] = [
        "physical": "productivity",
        "mental": "stoic",
        "emotional": "mindfulness",
        "spiritual": "wisdom"
    ]

    private func selectCategory(
        compassScores: [String: Double]?,
        currentMood: Int?,
        streak: Int,
        daySeed: Int
    ) -> String {
        let hour = Calendar.current.component(.hour, from: Date())

        // Context overrides:

        // Low mood -> stoic/comforting quotes
        if let mood = currentMood, mood <= 2 {
            return "stoic"
        }

        // Broken streak (0 after having had one) -> wisdom (compassionate)
        if streak == 0 {
            return "wisdom"
        }

        // High streak -> mix of stoic grit + wisdom perseverance
        if streak >= 7 && daySeed % 3 == 0 {
            return "stoic"
        }

        // Time-of-day bias
        if hour < 10 && daySeed % 4 == 0 {
            return "productivity"  // Morning -> energizing
        }
        if hour >= 20 && daySeed % 4 == 0 {
            return "mindfulness"  // Evening -> reflective
        }

        // 70/20/10 blend using compass scores
        guard let scores = compassScores, !scores.isEmpty else {
            // No compass data -> use wisdom pool
            return "wisdom"
        }

        let sorted = scores.sorted { $0.value > $1.value }
        let strongestDimension = sorted.first?.key ?? "spiritual"
        let weakestDimension = sorted.last?.key ?? "spiritual"

        let strongest = Self.dimensionToCategoryMap[strongestDimension] ?? "wisdom"
        let weakest = Self.dimensionToCategoryMap[weakestDimension] ?? "wisdom"

        // Use daySeed to deterministically select the blend ratio
        let blendSelector = daySeed % 10
        switch blendSelector {
        case 0:       // 10% -> wisdom (general inspiration)
            return "wisdom"
        case 1, 2:    // 20% -> weakest area (gentle nudge)
            return weakest
        default:      // 70% -> strongest area (reinforcement)
            return strongest
        }
    }
}
