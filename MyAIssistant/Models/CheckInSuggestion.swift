import Foundation
import SwiftData

@Model
final class CheckInSuggestion {
    var id: String
    var typeRaw: String
    var targetWindowRaw: String?
    var reason: String
    var suggestedHour: Int?
    var suggestedMinute: Int?
    var statusRaw: String
    var createdAt: Date
    var dismissedUntil: Date?

    @Transient
    var type: SuggestionType {
        get { SuggestionType(rawValue: typeRaw) ?? .disableWindow }
        set { typeRaw = newValue.rawValue }
    }

    @Transient
    var status: SuggestionStatus {
        get { SuggestionStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var isPending: Bool {
        status == .pending
    }

    var isDismissedAndCoolingDown: Bool {
        guard status == .dismissed, let until = dismissedUntil else { return false }
        return Date() < until
    }

    var icon: String {
        switch type {
        case .disableWindow: return "xmark.circle"
        case .adjustTime: return "clock.arrow.2.circlepath"
        case .addWindow: return "plus.circle"
        }
    }

    var suggestedTimeString: String? {
        guard let hour = suggestedHour else { return nil }
        let minute = suggestedMinute ?? 0
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }

    init(
        id: String = UUID().uuidString,
        type: SuggestionType,
        targetWindowRaw: String? = nil,
        reason: String,
        suggestedHour: Int? = nil,
        suggestedMinute: Int? = nil,
        status: SuggestionStatus = .pending,
        createdAt: Date = Date(),
        dismissedUntil: Date? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.targetWindowRaw = targetWindowRaw
        self.reason = reason
        self.suggestedHour = suggestedHour
        self.suggestedMinute = suggestedMinute
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.dismissedUntil = dismissedUntil
    }
}

// MARK: - Supporting Enums

enum SuggestionType: String, Codable {
    case disableWindow = "disable_window"
    case adjustTime = "adjust_time"
    case addWindow = "add_window"
}

enum SuggestionStatus: String, Codable {
    case pending
    case accepted
    case dismissed
}
