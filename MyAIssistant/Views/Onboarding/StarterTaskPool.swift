import Foundation

/// A template for a starter task suggested during onboarding.
struct StarterTask: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let dimension: LifeDimension
}

/// Provides hardcoded starter task templates organized by dimension.
/// No AI or network required — instant, offline, curated.
enum StarterTaskPool {

    // MARK: - Selection Logic

    /// Returns the weakest dimension from onboarding ratings.
    /// Tie-break order: Physical > Emotional > Mental > Spiritual (most actionable first).
    static func weakestDimension(from ratings: [LifeDimension: Int]) -> LifeDimension {
        let priority: [LifeDimension] = [.physical, .emotional, .mental, .spiritual]
        let minScore = priority.compactMap { ratings[$0] }.min() ?? 5
        return priority.first { ratings[$0] == minScore } ?? .physical
    }

    /// Returns 3 randomized tasks for the weakest dimension.
    static func tasksForWeakest(ratings: [LifeDimension: Int]) -> [StarterTask] {
        let dim = weakestDimension(from: ratings)
        let pool = tasks(for: dim)
        return Array(pool.shuffled().prefix(3))
    }

    // MARK: - Task Pools

    static func tasks(for dimension: LifeDimension) -> [StarterTask] {
        switch dimension {
        case .physical:  return physicalTasks
        case .mental:    return mentalTasks
        case .emotional: return emotionalTasks
        case .spiritual: return spiritualTasks
        case .practical: return []
        }
    }

    private static let physicalTasks: [StarterTask] = [
        StarterTask(title: "Take a 20-minute walk today", icon: "🚶", dimension: .physical),
        StarterTask(title: "Drink 8 glasses of water", icon: "💧", dimension: .physical),
        StarterTask(title: "Go to bed 30 minutes earlier tonight", icon: "🌙", dimension: .physical),
        StarterTask(title: "Do a 10-minute stretch or yoga session", icon: "🧘", dimension: .physical),
        StarterTask(title: "Cook one healthy meal", icon: "🥗", dimension: .physical),
        StarterTask(title: "Try a 7-minute bodyweight workout", icon: "💪", dimension: .physical),
    ]

    private static let mentalTasks: [StarterTask] = [
        StarterTask(title: "Read for 20 minutes", icon: "📚", dimension: .mental),
        StarterTask(title: "Write down 3 things you want to learn this month", icon: "📝", dimension: .mental),
        StarterTask(title: "Try a new podcast on a topic you're curious about", icon: "🎧", dimension: .mental),
        StarterTask(title: "Spend 15 minutes on a puzzle or brain game", icon: "🧩", dimension: .mental),
        StarterTask(title: "Organize your workspace for 10 minutes", icon: "🧹", dimension: .mental),
        StarterTask(title: "Write a journal entry about what's on your mind", icon: "✍️", dimension: .mental),
    ]

    private static let emotionalTasks: [StarterTask] = [
        StarterTask(title: "Text or call someone you haven't talked to in a while", icon: "📞", dimension: .emotional),
        StarterTask(title: "Write down 3 things you're grateful for", icon: "🙏", dimension: .emotional),
        StarterTask(title: "Take 10 minutes for something that brings you joy", icon: "🌟", dimension: .emotional),
        StarterTask(title: "Have a screen-free meal with someone you care about", icon: "👫", dimension: .emotional),
        StarterTask(title: "Write a kind note or message to someone", icon: "💌", dimension: .emotional),
        StarterTask(title: "Spend 15 minutes in nature without your phone", icon: "🌲", dimension: .emotional),
    ]

    private static let spiritualTasks: [StarterTask] = [
        StarterTask(title: "Text someone you appreciate and tell them why", icon: "💌", dimension: .spiritual),
        StarterTask(title: "Help a family member with something on their plate", icon: "👨‍👩‍👧", dimension: .spiritual),
        StarterTask(title: "Teach someone one skill you're good at", icon: "💡", dimension: .spiritual),
        StarterTask(title: "Spend 15 minutes truly listening to someone", icon: "👂", dimension: .spiritual),
        StarterTask(title: "Find one way to volunteer your skills this week", icon: "🙌", dimension: .spiritual),
        StarterTask(title: "Cook extra food and share it with a neighbor", icon: "🍲", dimension: .spiritual),
        StarterTask(title: "Call an older family member just to check in", icon: "📱", dimension: .spiritual),
        StarterTask(title: "Write a genuine recommendation for someone", icon: "⭐", dimension: .spiritual),
    ]
}
