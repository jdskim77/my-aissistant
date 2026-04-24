import Foundation
import SwiftData
import SwiftUI

@Model
final class HabitItem {
    var id: String = UUID().uuidString
    var title: String = ""
    var icon: String = "✅"          // emoji
    var colorHex: String = "#2D5016" // hex color for display
    var createdAt: Date = Date()
    var archivedAt: Date?
    var targetDaysRaw: String = "daily"  // comma-separated day numbers, or "daily"
    var reminderHour: Int?
    var reminderMinute: Int?

    /// `HabitTimeWindow.rawValue` or nil for all-day. Used for nudge
    /// targeting and visual emphasis only — **never** gates streak
    /// credit (see `currentStreak()` invariant comment). nil preserves
    /// legacy behavior for every habit created before this field
    /// existed; lightweight SwiftData migration handles the additive
    /// change without a new schema version.
    var timeWindowRaw: String?

    /// Comma-separated `LifeDimension` raw values. Nil = untagged (existing
    /// habits before this field was introduced). Tagged habits feed their
    /// Compass quadrant when completed; untagged habits don't pulse.
    var dimensionRaw: String?

    /// Tracks which dates this habit was completed on.
    /// Stored as comma-separated "yyyy-MM-dd" strings for SwiftData compatibility.
    var completionDatesRaw: String = ""

    /// Dates the user explicitly marked as missed (distinct from "not yet
    /// completed"). Mutually exclusive with `completionDates` — marking a date
    /// missed clears any completion for that day, and completing a date clears
    /// any missed flag. Stored as comma-separated "yyyy-MM-dd" strings.
    var missedDatesRaw: String = ""

    // MARK: - Computed

    @Transient
    var isArchived: Bool { archivedAt != nil }

    /// All life dimensions tagged on this habit. A habit can tag multiple
    /// dimensions (e.g., "family walk" = Physical + Emotional), matching
    /// `TaskItem.dimensions` semantics.
    @Transient
    var dimensions: [LifeDimension] {
        get {
            guard let raw = dimensionRaw, !raw.isEmpty else { return [] }
            return raw.split(separator: ",")
                .compactMap { LifeDimension(rawValue: String($0)) }
        }
        set {
            dimensionRaw = newValue.isEmpty ? nil :
                newValue.sorted(by: { $0.rawValue < $1.rawValue }).map(\.rawValue).joined(separator: ",")
        }
    }

    /// Convenience: primary (first) dimension for single-dimension code paths.
    @Transient
    var dimension: LifeDimension? {
        get { dimensions.first }
        set { dimensions = newValue.map { [$0] } ?? [] }
    }

    /// The color this habit should paint itself with in list rows, checkboxes,
    /// and other accents. Prefers the dimension color when tagged so the
    /// habit visually identifies with its Compass quadrant; otherwise falls
    /// back to the user's manual `colorHex` pick.
    @Transient
    var effectiveColor: Color {
        dimensions.primaryScored?.color ?? Color(hex: colorHex)
    }

    @Transient
    var targetDays: HabitFrequency {
        get { HabitFrequency(raw: targetDaysRaw) }
        set { targetDaysRaw = newValue.raw }
    }

    @Transient
    var completionDates: Set<String> {
        get {
            guard !completionDatesRaw.isEmpty else { return [] }
            return Set(completionDatesRaw.split(separator: ",").map(String.init))
        }
        set {
            completionDatesRaw = newValue.sorted().joined(separator: ",")
        }
    }

    @Transient
    var missedDates: Set<String> {
        get {
            guard !missedDatesRaw.isEmpty else { return [] }
            return Set(missedDatesRaw.split(separator: ",").map(String.init))
        }
        set {
            missedDatesRaw = newValue.sorted().joined(separator: ",")
        }
    }

    /// Time-of-day window this habit belongs to, or nil for all-day.
    /// Affects visual emphasis (dim outside window) and nudge targeting;
    /// never affects streak credit.
    @Transient
    var timeWindow: HabitTimeWindow? {
        get { timeWindowRaw.flatMap(HabitTimeWindow.init(rawValue:)) }
        set { timeWindowRaw = newValue?.rawValue }
    }

    /// Computes the habit's window state at a given instant. `now` is a
    /// parameter (not captured via `Date()` inside the body) so views can
    /// drive the value from `TimelineView.date` for auto-re-render at
    /// window boundaries, and tests can inject a deterministic clock.
    /// Returns `.allDay` when the habit has no time-window set — the
    /// legacy state for every habit created before windowing shipped.
    ///
    /// **Timezone is intentionally the device's current timezone, not
    /// the one at creation time.** "Morning stretches" means mornings
    /// where the user physically is, not mornings back home. A traveler
    /// in Tokyo doing stretches at 7am JST sees full opacity; the same
    /// user in PST earlier that day saw full opacity at 7am PST. This
    /// is the behavior Thrivn's users consistently prefer over pinning
    /// the tz to the record. (BUG-01.)
    func windowState(at now: Date = Date(), calendar: Calendar = .current) -> HabitWindowState {
        guard let window = timeWindow else { return .allDay }
        let hour = calendar.component(.hour, from: now)
        return window.contains(hour: hour) ? .inWindow : .outOfWindow
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        icon: String = "✅",
        colorHex: String = "#2D5016",
        targetDays: HabitFrequency = .daily,
        dimension: LifeDimension? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.colorHex = colorHex
        self.createdAt = Date()
        self.archivedAt = nil
        self.targetDaysRaw = targetDays.raw
        self.reminderHour = nil
        self.reminderMinute = nil
        self.completionDatesRaw = ""
        self.dimensionRaw = dimension?.rawValue
    }

    // MARK: - Helpers

    private static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        // Pin locale/calendar so keys written on one device (or one locale)
        // parse identically everywhere. Without this, a Japanese-era device
        // writes "R08-04-20" and breaks all lookups; a non-POSIX locale can
        // reformat separators and drift the key across days.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    func dateKey(for date: Date) -> String {
        Self.dateKeyFormatter.string(from: date)
    }

    func isCompletedOn(_ date: Date) -> Bool {
        completionDates.contains(dateKey(for: date))
    }

    func toggleCompletion(for date: Date) {
        let key = dateKey(for: date)
        var dates = completionDates
        if dates.contains(key) {
            dates.remove(key)
        } else {
            dates.insert(key)
            // Invariant: a date is never in both sets. Completing a day
            // clears any prior "missed" flag so the state stays consistent.
            var missed = missedDates
            if missed.remove(key) != nil {
                missedDates = missed
            }
        }
        completionDates = dates
    }

    func isMissedOn(_ date: Date) -> Bool {
        let key = dateKey(for: date)
        let missed = missedDates.contains(key)
        // Defense-in-depth: if the mutually-exclusive invariant was violated
        // (e.g. by a corrupted store or an external writer), treat the day as
        // completed — completion is the more user-positive state — so the UI
        // doesn't render contradictory "done + missed" markers.
        if missed, completionDates.contains(key) { return false }
        return missed
    }

    func markMissed(for date: Date) {
        let key = dateKey(for: date)
        var completed = completionDates
        if completed.remove(key) != nil {
            completionDates = completed
        }
        var missed = missedDates
        missed.insert(key)
        missedDates = missed
    }

    func unmarkMissed(for date: Date) {
        let key = dateKey(for: date)
        var missed = missedDates
        if missed.remove(key) != nil {
            missedDates = missed
        }
    }

    /// Current streak counting back from today.
    /// Skips non-target days for specific-day habits (e.g., Mon/Wed/Fri).
    ///
    /// **Invariant — streak credit is independent of `timeWindow`.**
    /// Completing a "morning stretches" habit at 2pm still earns today's
    /// streak credit. The time-window is for nudge targeting and visual
    /// emphasis only. Entangling streak math with window membership
    /// produced goal-gradient disillusionment in the behavioral-science
    /// review and was explicitly rejected.
    func currentStreak() -> Int {
        let cal = Calendar.current
        var streak = 0
        var checkDate = cal.startOfDay(for: Date())

        // If today isn't completed yet (and it's a target day), start from yesterday
        if targetDays.appliesTo(date: checkDate) && !isCompletedOn(checkDate) {
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        } else if !targetDays.appliesTo(date: checkDate) {
            // Today isn't a target day — start checking from yesterday
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        // Walk back up to 90 days, skipping non-target days
        for _ in 0..<90 {
            if targetDays.appliesTo(date: checkDate) {
                if isCompletedOn(checkDate) {
                    streak += 1
                } else {
                    break // Missed a target day — streak ends
                }
            }
            // Skip non-target days (don't count, don't break)
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
        return streak
    }

    /// Number of TARGET days since this habit was last completed, counting back
    /// from `asOf` (default today). Non-target days (e.g., Saturdays for a
    /// weekday-only habit) don't count toward the overdue tally — a Mon/Wed/Fri
    /// habit completed on Friday is 0 days overdue on Monday morning, because
    /// the weekend wasn't a target.
    ///
    /// Returns nil if the habit has never been completed.
    /// Returns 0 if the habit was completed today or today isn't a target day yet.
    func daysSinceLastCompletion(asOf date: Date = Date()) -> Int? {
        guard !completionDates.isEmpty else { return nil }
        let cal = Calendar.current
        var checkDate = cal.startOfDay(for: date)
        var missedTargetDays = 0

        // Look back up to 90 days for the most recent completion
        for _ in 0..<90 {
            if isCompletedOn(checkDate) { return missedTargetDays }
            if targetDays.appliesTo(date: checkDate) { missedTargetDays += 1 }
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
        return missedTargetDays
    }

    /// Completion rate over the last N days.
    func completionRate(days: Int = 30) -> Double {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var completed = 0
        var applicable = 0

        for offset in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            if targetDays.appliesTo(date: date) {
                applicable += 1
                if isCompletedOn(date) { completed += 1 }
            }
        }

        return applicable > 0 ? Double(completed) / Double(applicable) : 0
    }
}

// MARK: - Habit Time Window

/// Fuzzy 4-hour band a habit belongs to. Window membership controls
/// visual emphasis (in-window = full opacity, out-of-window = dimmed)
/// and nudge targeting. Streak credit is always day-scoped, never
/// window-scoped.
///
/// Hour ranges are centered on the corresponding `CheckInTime.hour` so
/// the window taxonomy aligns with the check-in slots users already
/// know. Night is `20...23` with no post-midnight wrap in v1 — learned
/// from dogfood before adding complexity.
enum HabitTimeWindow: String, CaseIterable, Identifiable {
    case morning
    case midday
    case afternoon
    case night

    var id: String { rawValue }

    /// True when the given hour-of-day (0-23) is inside this window.
    /// Morning/midday/afternoon are contiguous inclusive bands anchored
    /// to the matching `CheckInTime.hour`. **Night wraps past midnight**
    /// (20-23 + 0-1) so a bedtime habit done at 00:30 still reads as
    /// in-window — matches the user's mental model of "late night"
    /// (BUG-02 fix). Hours 2-5 remain outside any window: those are
    /// sleep hours when the user is not interacting with the app.
    func contains(hour: Int) -> Bool {
        switch self {
        case .morning:   return (6...10).contains(hour)
        case .midday:    return (11...15).contains(hour)
        case .afternoon: return (16...19).contains(hour)
        case .night:     return hour >= 20 || hour <= 1
        }
    }

    var label: String {
        switch self {
        case .morning:   return "Morning"
        case .midday:    return "Midday"
        case .afternoon: return "Afternoon"
        case .night:     return "Night"
        }
    }

    /// The hour that divides this window's first half from its second
    /// half. Consumed by the nudge engine to decide "the window is half
    /// gone and the habit is still open" — earlier firing would be
    /// impatient, later firing wouldn't leave room to act.
    var midpointHour: Int {
        switch self {
        case .morning:   return 8    // 6-10, midpoint 8
        case .midday:    return 13   // 11-15, midpoint 13
        case .afternoon: return 18   // 16-19, midpoint 17.5 → 18
        case .night:     return 23   // 20-1, midpoint 22.5 → 23
        }
    }

    /// True when the given hour-of-day is at-or-past this window's
    /// midpoint. Wrap-aware for `.night`: past-midpoint covers `23` and
    /// the post-midnight tail `0...1`.
    func isPastMidpoint(hour: Int) -> Bool {
        switch self {
        case .morning, .midday, .afternoon:
            return hour >= midpointHour
        case .night:
            return hour >= 23 || hour <= 1
        }
    }

    /// SF Symbol, matching `CheckInTime.sfSymbol` so the two taxonomies
    /// read as one unified set when displayed side by side.
    var sfSymbol: String {
        switch self {
        case .morning:   return "sunrise.fill"
        case .midday:    return "sun.max.fill"
        case .afternoon: return "sunset.fill"
        case .night:     return "moon.stars.fill"
        }
    }
}

/// Rendering state derived from a habit's `timeWindow` and the current
/// instant. Two visual bands in v1 (per expert-review simplification);
/// can split further in v2 if dogfood shows a need.
enum HabitWindowState {
    /// No time-window set; legacy behavior. Full opacity.
    case allDay
    /// Time-window set and current hour is inside it. Full opacity.
    case inWindow
    /// Time-window set and current hour is outside it. Dim (0.5 opacity).
    case outOfWindow

    /// Opacity for row rendering. Kept as a single source of truth so
    /// the value matches everywhere a windowed habit is drawn.
    var opacity: Double {
        switch self {
        case .inWindow, .allDay: return 1.0
        case .outOfWindow:       return 0.5
        }
    }
}

// MARK: - Habit Frequency

enum HabitFrequency: Equatable {
    case daily
    case specificDays(Set<Int>) // 1=Sun ... 7=Sat (Calendar weekday)

    var raw: String {
        switch self {
        case .daily: return "daily"
        case .specificDays(let days):
            return days.sorted().map(String.init).joined(separator: ",")
        }
    }

    init(raw: String) {
        if raw == "daily" {
            self = .daily
        } else {
            let days = Set(raw.split(separator: ",").compactMap { Int($0) })
            self = days.isEmpty ? .daily : .specificDays(days)
        }
    }

    func appliesTo(date: Date) -> Bool {
        switch self {
        case .daily: return true
        case .specificDays(let days):
            let weekday = Calendar.current.component(.weekday, from: date)
            return days.contains(weekday)
        }
    }

    var displayLabel: String {
        switch self {
        case .daily: return "Every day"
        case .specificDays(let days):
            let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            return days.sorted().map { names[$0] }.joined(separator: ", ")
        }
    }
}
