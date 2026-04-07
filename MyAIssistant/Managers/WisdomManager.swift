import Foundation
import Observation
import SwiftData

@Observable @MainActor
final class WisdomManager {
    struct Quote: Codable {
        let text: String
        let author: String
        let dimension: String  // "physical", "mental", "emotional", "spiritual", "general"
    }

    private let modelContext: ModelContext
    // Process-local quote cache. Guarded by `cacheLock` so the legacy static
    // accessors used by Watch/Widget timeline code (which may run off the main
    // actor) cannot race with the @MainActor iOS app instance.
    nonisolated(unsafe) private static var cachedQuotes: [Quote]?
    private static let cacheLock = NSLock()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Quote Loading

    nonisolated static func loadQuotes() -> [Quote] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cachedQuotes { return cached }
        guard let url = Bundle.main.url(forResource: "DailyWisdom", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let quotes = try? JSONDecoder().decode([Quote].self, from: data) else {
            #if DEBUG
            print("[WisdomManager] Failed to load DailyWisdom.json")
            #endif
            return []
        }
        cachedQuotes = quotes
        return quotes
    }

    // MARK: - Intelligent Quote Selection (70/20/10)

    /// Returns today's quote using the 70/20/10 blend algorithm:
    /// - 70% of the time: quote from the user's STRONGEST dimension (reinforcement)
    /// - 20% of the time: quote from the user's WEAKEST dimension (gentle nudge)
    /// - 10% of the time: general inspiration quote
    ///
    /// Context overrides:
    /// - Morning → physical/energizing
    /// - Evening → emotional/reflective
    /// - Low mood → emotional (comforting)
    /// - High streak (7+) → general (grit/perseverance)
    func todayQuote(
        compassScores: [String: Double]? = nil,
        currentMood: Int? = nil,
        streak: Int = 0
    ) -> Quote? {
        let quotes = Self.loadQuotes()
        guard !quotes.isEmpty else { return nil }

        let daySeed = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0

        let targetDimension = selectDimension(
            compassScores: compassScores,
            currentMood: currentMood,
            streak: streak,
            daySeed: daySeed
        )

        let pool = quotes.filter { $0.dimension == targetDimension }
        guard !pool.isEmpty else {
            return quotes[daySeed % quotes.count]
        }

        return pool[daySeed % pool.count]
    }

    /// Legacy static method for backward compatibility (Watch, Widgets).
    /// Nonisolated so widget timeline providers can call it from non-Main contexts.
    nonisolated static func todayQuote() -> Quote? {
        let quotes = loadQuotes()
        guard !quotes.isEmpty else { return nil }
        let daySeed = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return quotes[daySeed % quotes.count]
    }

    // MARK: - Dimension Selection Logic

    private func selectDimension(
        compassScores: [String: Double]?,
        currentMood: Int?,
        streak: Int,
        daySeed: Int
    ) -> String {
        let hour = Calendar.current.component(.hour, from: Date())

        // Context overrides:

        // Low mood → emotional/comforting quotes
        if let mood = currentMood, mood <= 2 {
            return "emotional"
        }

        // High streak → sprinkle in general grit quotes
        if streak >= 7 && daySeed % 3 == 0 {
            return "general"
        }

        // Morning bias → physical/energizing
        if hour < 10 && daySeed % 4 == 0 {
            return "physical"
        }

        // Evening bias → emotional/reflective
        if hour >= 20 && daySeed % 4 == 0 {
            return "emotional"
        }

        // 70/20/10 blend using compass scores
        guard let scores = compassScores, !scores.isEmpty else {
            return "general"
        }

        let sorted = scores.sorted { $0.value > $1.value }
        let strongest = sorted.first?.key ?? "general"
        let weakest = sorted.last?.key ?? "general"

        let blendSelector = daySeed % 10
        switch blendSelector {
        case 0:       // 10% → general
            return "general"
        case 1, 2:    // 20% → weakest dimension (gentle nudge)
            return weakest
        default:      // 70% → strongest dimension (reinforcement)
            return strongest
        }
    }
}
