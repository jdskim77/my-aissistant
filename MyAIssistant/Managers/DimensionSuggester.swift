import Foundation
import SwiftData

/// Suggests a LifeDimension for a task based on learned user preferences,
/// keyword matching, and category fallback — in that priority order.
enum DimensionSuggester {

    /// Suggestion result with confidence level.
    struct Suggestion {
        let dimension: LifeDimension
        let confidence: SuggestionConfidence
    }

    enum SuggestionConfidence {
        case learned    // User has consistently tagged this keyword → pre-select
        case keyword    // Keyword match from static list → suggest (sparkle chip)
        case category   // Category fallback → suggest (sparkle chip)
    }

    /// Returns suggested dimensions (1-3) with confidence, ordered by signal strength.
    /// Multi-word titles can match multiple dimensions (e.g., "family walk" → Physical + Emotional).
    static func suggestMultiple(
        title: String,
        category: TaskCategory? = nil,
        context: ModelContext? = nil
    ) -> [Suggestion] {
        let lower = title.lowercased()
        var results: [Suggestion] = []
        var seen: Set<LifeDimension> = []

        // 1. Check learned user preferences (highest priority)
        if let context {
            if let learned = learnedPreference(for: lower, in: context), !seen.contains(learned) {
                results.append(Suggestion(dimension: learned, confidence: .learned))
                seen.insert(learned)
            }
        }

        // 2. Check keyword lists — collect ALL matching dimensions
        for (dimension, keywords) in keywordMap where !seen.contains(dimension) {
            if keywords.contains(where: { lower.contains($0) }) {
                results.append(Suggestion(dimension: dimension, confidence: .keyword))
                seen.insert(dimension)
            }
        }

        // 3. Fall back to category heuristic (only if no keyword matches)
        if results.isEmpty, let category, let dim = categoryMapping[category], !seen.contains(dim) {
            results.append(Suggestion(dimension: dim, confidence: .category))
        }

        // Cap at 3 suggestions max
        return Array(results.prefix(3))
    }

    /// Returns a single suggested dimension with confidence, or nil if no signal.
    /// Backward compatible — returns the strongest single suggestion.
    static func suggest(
        title: String,
        category: TaskCategory? = nil,
        context: ModelContext? = nil
    ) -> Suggestion? {
        suggestMultiple(title: title, category: category, context: context).first
    }

    /// Convenience: returns just the dimension (backward compatible).
    static func suggest(title: String, category: TaskCategory? = nil) -> LifeDimension? {
        suggest(title: title, category: category, context: nil)?.dimension
    }

    /// Record that the user tagged a task with specific dimensions.
    /// Call this when a task is saved with dimension tags.
    /// Uses the PRIMARY (first) dimension for preference learning to avoid
    /// inflating totalCount — one observation per keyword per save.
    static func recordPreference(title: String, dimensions: [LifeDimension], context: ModelContext) {
        guard let primary = dimensions.first else { return }
        let keywords = extractKeywords(from: title)
        for keyword in keywords {
            let descriptor = FetchDescriptor<UserDimensionPreference>(
                predicate: #Predicate { $0.keyword == keyword }
            )
            if let existing = try? context.fetch(descriptor).first {
                existing.totalCount += 1
                if existing.dimension == primary {
                    existing.confirmCount += 1
                } else if existing.confirmCount < existing.totalCount / 2 {
                    existing.dimension = primary
                    existing.confirmCount = 1
                    existing.totalCount = 2
                }
                existing.lastUpdated = Date()
            } else {
                let pref = UserDimensionPreference(keyword: keyword, dimension: primary)
                context.insert(pref)
            }
        }
        context.safeSave()
    }

    /// Backward-compatible single-dimension version.
    static func recordPreference(title: String, dimension: LifeDimension, context: ModelContext) {
        recordPreference(title: title, dimensions: [dimension], context: context)
    }

    // MARK: - Private Helpers

    /// Look up the user's learned preference for any keyword in the title.
    private static func learnedPreference(for lowerTitle: String, in context: ModelContext) -> LifeDimension? {
        let keywords = extractKeywords(from: lowerTitle)
        for keyword in keywords {
            let descriptor = FetchDescriptor<UserDimensionPreference>(
                predicate: #Predicate { $0.keyword == keyword }
            )
            if let pref = try? context.fetch(descriptor).first,
               pref.confidence >= 0.6, pref.totalCount >= 2 {
                return pref.dimension
            }
        }
        return nil
    }

    /// Extract meaningful keywords from a title (2+ characters, skip stop words).
    private static func extractKeywords(from title: String) -> [String] {
        let stopWords: Set<String> = ["the", "a", "an", "to", "for", "and", "or", "my", "in", "at", "on", "with", "do", "go"]
        return title.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
    }

    // MARK: - Keyword Map

    /// Keywords grouped by dimension. Order within each list doesn't matter;
    /// multi-word phrases are checked via `contains` so "ice bath" matches "take an ice bath".
    private static let keywordMap: [LifeDimension: [String]] = [
        .physical: [
            // Exercise
            "run", "jog", "walk", "hike", "swim", "bike", "cycle", "gym", "workout", "exercise",
            "lift", "yoga", "stretch", "pilates", "crossfit", "cardio", "training", "sprint",
            "pushup", "squat", "plank", "basketball", "soccer", "tennis", "golf", "climb",
            // Health
            "doctor", "dentist", "checkup", "physical", "physical therapy", "physio", "chiropractor",
            "prescription", "medication", "vitamins", "supplement", "blood test", "x-ray",
            "vaccine", "flu shot",
            // Sleep & nutrition
            "sleep", "nap", "meal prep", "cook", "nutrition", "diet", "hydrate", "water intake",
            "smoothie", "protein", "ice bath", "sauna",
        ],

        .mental: [
            // Learning
            "read", "study", "learn", "course", "class", "lecture", "tutorial", "research",
            "book", "article", "podcast", "audiobook", "homework",
            // Creative / professional
            "write", "code", "design", "brainstorm", "plan", "strategize", "analyze",
            "presentation", "project", "review", "report", "budget", "spreadsheet",
            // Growth
            "certification", "exam", "practice", "skill", "language", "puzzle", "chess",
            "journal",
        ],

        .emotional: [
            // Social
            "call", "text", "message", "visit", "dinner with", "lunch with", "coffee with",
            "date night", "date", "hang out", "hangout", "party", "get together",
            "friend", "family", "mom", "dad", "parent", "sibling", "brother", "sister",
            "grandma", "grandpa",
            // Celebrations
            "birthday", "anniversary", "celebrate", "gift", "card for", "surprise",
            // Self-care
            "therapy", "counseling", "self-care", "spa", "massage", "relax", "movie",
            "game night", "board game", "fun",
        ],

        .spiritual: [
            // Meditation & mindfulness
            "meditat", "mindful", "breathe", "breathing", "pray", "prayer", "church",
            "mosque", "temple", "synagogue", "worship", "sermon",
            // Reflection
            "gratitude", "reflect", "contemplat", "devotion", "scripture", "bible",
            "quran", "journal reflect",
            // Selfless service & helping others
            "volunteer", "donate", "charity", "help others", "community service",
            "shelter", "food bank", "food drive", "mentor", "coach",
            "give back", "serve", "service project", "fundrais", "nonprofit",
            "tutor", "teach for", "soup kitchen", "habitat", "red cross",
            "random act", "kindness", "lend a hand", "favor for",
            // Nature & purpose
            "nature walk", "forest", "sunset", "sunrise", "garden",
        ],

        .practical: [
            // Errands
            "grocery", "groceries", "shopping", "errand", "laundry", "clean", "dishes",
            "vacuum", "mop", "organize", "declutter", "trash", "recycl",
            // Admin
            "bill", "pay", "tax", "insurance", "renew", "appointment",
            "paperwork", "mail", "package", "return", "refund",
            "oil change", "car wash", "repair", "fix", "maintenance",
            "bank", "DMV", "license",
        ],
    ]

    // MARK: - Category Fallback

    /// Maps existing TaskCategory to a likely LifeDimension when keywords don't match.
    private static let categoryMapping: [TaskCategory: LifeDimension] = [
        .health: .physical,
        .work: .mental,
        .personal: .emotional,
        .travel: .practical,
        .errand: .practical,
    ]
}
