#if os(watchOS)
import Foundation

// MARK: - Engine / Reusable (with domain-specific fields flagged below)
//
// iPhone → Watch sync payload. Transport pattern is generic — JSON-encoded,
// passed via `applicationContext` (latest-value-wins). The TYPE SHAPE,
// however, contains Thrivn-specific fields.
//
// REUSABLE (keep in fork):
//   - tasks, streakDays, completedToday, totalToday
//   - quoteText / quoteAuthor
//   - updatedAt, userName
//   - Codable/dictionary encoding scaffold (`toDictionary()` / `from(context:)`)
//   - WatchTask sub-struct
//
// ⚠️ THRIVN-SPECIFIC — REPLACE IN FORK:
//   - `bodyScore` / `mindScore` / `heartScore` / `spiritScore`
//     → swap for your app's dimensions, OR switch to a generic
//       `dimensionScores: [String: Double]?` dictionary
//   - `aiInsight` (phrased for daily recap wording) — rename or repurpose
//   - `nextCheckIn` / `completedCheckIns` — Thrivn's 4-slot daily check-in
//     framework; replace with whatever cadence the fork uses
//
// The transport scaffold (encode/decode, applicationContext dictionary wrapper)
// is the real reusable asset here. The field names are only a pattern.
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

    // Compass dimension scores (0-10). Nil = not enough data yet.
    let bodyScore: Double?
    let mindScore: Double?
    let heartScore: Double?
    let spiritScore: Double?

    // User info
    let userName: String?
    let aiInsight: String? // Latest daily recap line

    // Check-in status for today (which slots are completed)
    let completedCheckIns: [String]? // e.g. ["Morning", "Midday"]

    // Backward-compatible initializer
    init(
        tasks: [WatchTask],
        streakDays: Int,
        completedToday: Int,
        totalToday: Int,
        quoteText: String?,
        quoteAuthor: String?,
        nextCheckIn: String?,
        updatedAt: Date,
        bodyScore: Double? = nil,
        mindScore: Double? = nil,
        heartScore: Double? = nil,
        spiritScore: Double? = nil,
        userName: String? = nil,
        aiInsight: String? = nil,
        completedCheckIns: [String]? = nil
    ) {
        self.tasks = tasks
        self.streakDays = streakDays
        self.completedToday = completedToday
        self.totalToday = totalToday
        self.quoteText = quoteText
        self.quoteAuthor = quoteAuthor
        self.nextCheckIn = nextCheckIn
        self.updatedAt = updatedAt
        self.bodyScore = bodyScore
        self.mindScore = mindScore
        self.heartScore = heartScore
        self.spiritScore = spiritScore
        self.userName = userName
        self.aiInsight = aiInsight
        self.completedCheckIns = completedCheckIns
    }

    struct WatchTask: Codable, Identifiable, Hashable {
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
    