#if os(watchOS)
import Foundation

/// Shared data synced from iPhone → Watch via WatchConnectivity.
/// Both targets include this file.
struct WatchScheduleData: Codable {
    let tasks: [WatchTask]
    let streakDays: Int
    let completedToday: Int
    let totalToday: Int
    let quoteText: String?
    let quoteAuthor: String?
    let nextCheckIn: String? // e.g. "Morning" or nil if all done
    let updatedAt: Date

    struct WatchTask: Codable, Identifiable {
        let id: String
        let title: String
        let date: Date
        let priorityRaw: String
        let categoryRaw: String
        let done: Bool
        let isCalendarEvent: Bool
        let recurrenceRaw: String?

        var hasTime: Bool {
            let cal = Calendar.current
            let h = cal.component(.hour, from: date)
            let m = cal.component(.minute, from: date)
            return h != 0 || m != 0
        }

        private static let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return f
        }()

        var timeString: String {
            Self.timeFormatter.string(from: date)
        }

        var priorityInitial: String {
            switch priorityRaw {
            case "High": return "H"
            case "Medium": return "M"
            case "Low": return "L"
            default: return ""
            }
        }
    }

    /// Encode to dictionary for WatchConnectivity applicationContext.
    func toDictionary() -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return ["watchScheduleDict": dict]
    }

    /// Decode from WatchConnectivity applicationContext
    static func from(context: [String: Any]) -> WatchScheduleData? {
        // Primary: dictionary-based transfer (correct approach)
        if let dict = context["watchScheduleDict"] as? [String: Any] {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? decoder.decode(WatchScheduleData.self, from: jsonData)
        }
        // Fallback: raw Data transfer (legacy)
        if let data = context["watchSchedule"] as? Data {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try? decoder.decode(WatchScheduleData.self, from: data)
        }
        return nil
    }
}
#endif
