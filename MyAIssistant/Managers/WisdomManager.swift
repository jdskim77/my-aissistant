import Foundation

/// Manages the daily wisdom quote — one quote per day, deterministic by date.
@MainActor
final class WisdomManager {
    struct Quote: Codable {
        let text: String
        let author: String
        let category: String
    }

    private static var cachedQuotes: [Quote]?

    /// Loads quotes from the bundled JSON, cached after first load.
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

    /// Returns today's quote, deterministically selected by date.
    /// Same quote all day, changes at midnight.
    static func todayQuote() -> Quote? {
        let quotes = loadQuotes()
        guard !quotes.isEmpty else { return nil }
        let daysSinceEpoch = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let index = daysSinceEpoch % quotes.count
        return quotes[index]
    }
}
