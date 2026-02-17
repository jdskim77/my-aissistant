import Foundation

enum TaskCategory: String, CaseIterable, Codable, Identifiable {
    case travel = "Travel"
    case errand = "Errand"
    case personal = "Personal"
    case work = "Work"
    case health = "Health"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .travel: return "✈️"
        case .errand: return "🏃"
        case .personal: return "🧘"
        case .work: return "💼"
        case .health: return "💪"
        }
    }
}
