import Foundation

/// Pure decision logic for the notification-driven "10-second mood check-in"
/// (Feature 1). Deliberately framework-free (no UserNotifications/SwiftData
/// imports) so every branch here is unit-testable without a ModelContainer
/// or a live notification center. The framework-heavy orchestration that
/// calls into this lives in `QuickCheckInHandler`.
enum QuickCheckInLogic {

    // MARK: - Mood Actions

    struct MoodActionSpec: Equatable {
        let identifier: String
        /// Emoji + word, matching MoodPicker's existing 5-point scale.
        let title: String
        let value: Int
    }

    /// The 5-point mood scale as notification actions, in display order.
    /// Mirrors `MoodPicker`'s emoji/label pairs (1 = Rough … 5 = Great).
    /// These are NOT `.foreground` actions — tapping one must not open the app.
    static let moodActionSpecs: [MoodActionSpec] = [
        MoodActionSpec(identifier: "MOOD_1", title: "😔 Rough", value: 1),
        MoodActionSpec(identifier: "MOOD_2", title: "😕 Low", value: 2),
        MoodActionSpec(identifier: "MOOD_3", title: "😐 Okay", value: 3),
        MoodActionSpec(identifier: "MOOD_4", title: "🙂 Good", value: 4),
        MoodActionSpec(identifier: "MOOD_5", title: "😄 Great", value: 5)
    ]

    static var moodActionIdentifiers: [String] { moodActionSpecs.map(\.identifier) }

    /// Returns the 1-5 mood value for a tapped notification action identifier,
    /// or nil when the identifier isn't one of the quick-mood actions (e.g.
    /// "COMPLETE_CHECKIN" or "DISMISS").
    static func moodValue(forActionIdentifier identifier: String) -> Int? {
        moodActionSpecs.first { $0.identifier == identifier }?.value
    }

    static func moodEmoji(for value: Int) -> String {
        moodActionSpecs.first { $0.value == value }?.title.split(separator: " ").first.map(String.init) ?? "😐"
    }

    static func moodLabel(for value: Int) -> String {
        switch value {
        case 1: return "Rough"
        case 2: return "Low"
        case 3: return "Okay"
        case 4: return "Good"
        default: return "Great"
        }
    }

    // MARK: - Slot Derivation

    /// Framework-free mirror of `CheckInTime`'s raw values, so this file has
    /// no dependency on the SwiftUI-importing model layer. The production
    /// call site maps this back to `CheckInTime(rawValue:)`.
    enum SlotName: String, CaseIterable {
        case morning = "Morning"
        case midday = "Midday"
        case afternoon = "Afternoon"
        case night = "Night"
    }

    /// CHECKIN notifications always carry an explicit `timeSlot` in userInfo
    /// and that wins. STREAK_REMINDER fires once a day with no slot, so the
    /// quick-mood action has to infer one from the current wall-clock hour.
    static func deriveTimeSlot(explicitRaw: String?, hour: Int) -> SlotName {
        if let explicitRaw, let slot = SlotName(rawValue: explicitRaw) {
            return slot
        }
        return slot(forHour: hour)
    }

    /// Boundaries sit at the midpoints between CheckInTime's own slot hours
    /// (morning 8, midday 13, afternoon 18, night 22), so a 2pm quick
    /// check-in tap lands on "midday" (the nearest slot) rather than
    /// whichever slot happens to come next chronologically.
    static func slot(forHour hour: Int) -> SlotName {
        switch hour {
        case 0..<3: return .night       // just after midnight still counts as last night
        case 3..<11: return .morning
        case 11..<16: return .midday
        case 16..<20: return .afternoon
        default: return .night          // 20...23
        }
    }

    // MARK: - Find-or-Create (no double-recording)

    enum Decision: Equatable {
        /// This slot already has a completed record today — do nothing.
        case alreadyCompleted
        /// A record exists for this slot today but isn't completed — complete it in place.
        case completeExistingPending
        /// No record exists for this slot today — create one, then complete it.
        case createAndComplete
    }

    struct ExistingRecordSummary: Equatable {
        let timeSlotRaw: String
        let completed: Bool
    }

    static func decide(for slot: SlotName, existingToday: [ExistingRecordSummary]) -> Decision {
        if existingToday.contains(where: { $0.timeSlotRaw == slot.rawValue && $0.completed }) {
            return .alreadyCompleted
        }
        if existingToday.contains(where: { $0.timeSlotRaw == slot.rawValue && !$0.completed }) {
            return .completeExistingPending
        }
        return .createAndComplete
    }

    // MARK: - Reward Notification Copy

    static func rewardNotificationTitle(moodValue: Int) -> String {
        "\(moodEmoji(for: moodValue)) Check-in logged"
    }

    /// "Logged: <mood>. 🔥 <streak>-day streak" plus today's insight text
    /// when available — the explicit link to Feature 2.
    static func rewardNotificationBody(moodValue: Int, streak: Int, insightText: String?) -> String {
        var body = "Logged: \(moodLabel(for: moodValue)). 🔥 \(streak)-day streak"
        if let insightText, !insightText.isEmpty {
            body += ". \(insightText)"
        }
        return body
    }

    // MARK: - Streak Reminder Next-Fire-Date (8pm-bug bonus fix)

    /// Computes the next fire date for the non-repeating streak-at-risk
    /// reminder. Framework-free so it's directly unit-testable.
    ///
    /// Previously the reminder used a `repeats: true` calendar trigger
    /// keyed only on hour/minute, which fires every single day at 8pm
    /// with no way to skip "today" once the user has already checked in —
    /// canceling it (`cancelStreakReminder`) only removed the pending
    /// request; the very next `scheduleAdaptiveCheckInReminders` call
    /// (on next app launch or next check-in) immediately re-armed a fresh
    /// repeating 8pm trigger that still fires *today* if 8pm hasn't
    /// passed yet. Non-repeating + explicit next-occurrence math fixes
    /// that: when `alreadyCheckedInToday` is true, or today's 8pm has
    /// already passed, the next fire date is tomorrow at `hour`:00;
    /// otherwise it's today at `hour`:00.
    static func nextStreakReminderFireDate(
        now: Date,
        alreadyCheckedInToday: Bool,
        hour: Int,
        calendar: Calendar = .current
    ) -> Date {
        let todayAtHour = calendar.date(
            bySettingHour: hour, minute: 0, second: 0, of: now
        ) ?? now
        let needsTomorrow = alreadyCheckedInToday || todayAtHour <= now
        if needsTomorrow {
            return calendar.date(byAdding: .day, value: 1, to: todayAtHour) ?? todayAtHour
        }
        return todayAtHour
    }

    // MARK: - Post-Check-in Insight Fallback (Feature 2)

    /// Shown in the in-app insight card when `InsightEngine.todayInsight()`
    /// returns nil (not enough data yet). Per NUDGE_ENGINE_SPEC's non-goals:
    /// factual, not cheerleading — no exclamation points, no "great job".
    static func fallbackInsightText() -> String {
        "A few more check-ins will unlock your first pattern insight."
    }
}
