import Foundation
import SwiftData
import SwiftUI

/// Computes weekly balance scores using a 3-signal composite model:
///   1. Activity Score (30%) — effort-weighted task completion vs personal target
///   2. Satisfaction Score (40%) — user's self-rated satisfaction from check-ins
///   3. Consistency Score (30%) — how many days this week had activity in the dimension
///
/// Balance Score penalizes imbalance: mean - 1.5 * stdev
/// Based on Wheel of Life (coaching), PERMA (Seligman), WHO-5, and SDT.
@Observable @MainActor
final class BalanceManager {
    private let modelContext: ModelContext

    /// Default weekly effort target per dimension. User can customize.
    private static let defaultTarget = 10

    /// Cache for weekly breakdowns — invalidated after 30 seconds or on data mutation.
    /// @ObservationIgnored prevents cache writes from triggering view re-renders (infinite loop).
    @ObservationIgnored private var cachedBreakdowns: [LifeDimension: DimensionBreakdown]?
    @ObservationIgnored private var cachedBreakdownsWeekStart: Date?
    @ObservationIgnored private var cacheTimestamp: Date?
    private static let cacheTTL: TimeInterval = 30

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Invalidate the cache (call after any data mutation).
    func invalidateCache() {
        cachedBreakdowns = nil
        cacheTimestamp = nil
    }

    private func isCacheValid(for weekStart: Date?) -> Bool {
        guard let cached = cachedBreakdowns,
              let ts = cacheTimestamp,
              Date().timeIntervalSince(ts) < Self.cacheTTL else { return false }
        // Only valid for current week (nil weekStart = current week)
        if weekStart == nil && cachedBreakdownsWeekStart == Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start {
            return true
        }
        return weekStart == cachedBreakdownsWeekStart
    }

    // MARK: - Composite Dimension Scores

    /// A breakdown of the three signals for one dimension.
    struct DimensionBreakdown {
        let activity: Double      // 0-10
        let satisfaction: Double  // 0-10
        let consistency: Double   // 0-10
        var composite: Double {
            activity * 0.30 + satisfaction * 0.40 + consistency * 0.30
        }
    }

    /// Returns composite scores (0-10) per scored dimension for the current week.
    func weeklyScores(for weekStart: Date? = nil) -> [LifeDimension: Double] {
        let breakdowns = weeklyBreakdowns(for: weekStart)
        return breakdowns.mapValues(\.composite)
    }

    /// Returns the full signal breakdown per dimension for the current week.
    /// Results are cached for 30 seconds to avoid redundant queries.
    func weeklyBreakdowns(for weekStart: Date? = nil) -> [LifeDimension: DimensionBreakdown] {
        if isCacheValid(for: weekStart), let cached = cachedBreakdowns {
            return cached
        }

        let calendar = Calendar.current
        let start = weekStart ?? calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let end = calendar.safeDate(byAdding: .day, value: 7, to: start)

        // Single fetch for tasks — shared between activity and consistency signals
        let taskDescriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= start && $0.date < end && $0.done == true }
        )
        let tasks = (try? modelContext.fetch(taskDescriptor)) ?? []

        // Habits are dimension-tagged completions too. Decode each habit's
        // completion-date strings and keep only those inside [start, end).
        // Cheap: `completionDatesRaw` is a comma-separated string per habit.
        let habitDescriptor = FetchDescriptor<HabitItem>(
            predicate: #Predicate { $0.archivedAt == nil }
        )
        let habits = (try? modelContext.fetch(habitDescriptor)) ?? []
        let habitCompletions = habitCompletions(in: habits, from: start, to: end)

        // Activity + consistency blend task and habit contributions. Tasks use
        // effort-split points; habits use a fixed 2 points per completion
        // (split across multi-tagged habits).
        var activityScores = activitySignalFromTasks(tasks)
        let habitActivity = activitySignalFromHabits(habitCompletions)
        for dim in LifeDimension.scored {
            activityScores[dim] = min(10, (activityScores[dim] ?? 0) + (habitActivity[dim] ?? 0))
        }

        let satisfactionScores = satisfactionSignal(from: start, to: end)

        var consistencyScores = consistencySignalFromTasks(tasks)
        let habitActiveDays = habitActiveDays(habitCompletions)
        for dim in LifeDimension.scored {
            // Blend by max(task-days, habit-days) converted to score space.
            // Combining raw day sets would overstate consistency (counting the
            // same Monday twice); taking the stronger signal keeps the score
            // reflective of "was this dimension active that day."
            let habitScore = Double(habitActiveDays[dim]?.count ?? 0) / 7.0 * 10
            consistencyScores[dim] = max(consistencyScores[dim] ?? 0, habitScore)
        }

        // Detect if user has ANY data this week (tasks or check-ins)
        let hasSatisfactionData = satisfactionScores.values.contains(where: { $0 != 5 })

        // Count total completed activities this week (tasks + habits) to
        // determine data maturity. With few completions, activity/consistency
        // signals are unreliable and drag the compass far below what the user
        // self-reported. Ramp gradually:
        //   0 activities  → 100% satisfaction (show what user rated)
        //   1-6          → blend: satisfaction dominates, activity/consistency fade in
        //   7+           → full weighted formula
        let totalCompletedTasks = tasks.count + habitCompletions.count
        let taskDataWeight = min(1.0, Double(totalCompletedTasks) / 7.0)

        var result: [LifeDimension: DimensionBreakdown] = [:]

        for dim in LifeDimension.scored {
            if hasSatisfactionData || totalCompletedTasks > 0 {
                let sat = satisfactionScores[dim] ?? 5
                let act = activityScores[dim] ?? 0
                let con = consistencyScores[dim] ?? 0

                // Blend: at 0 tasks, activity and consistency use satisfaction as floor.
                // At 7+ tasks, real values are used. This prevents the compass from
                // showing 3/10 when the user rated themselves 7/9 during onboarding.
                let blendedActivity = sat * (1 - taskDataWeight) + act * taskDataWeight
                let blendedConsistency = sat * (1 - taskDataWeight) + con * taskDataWeight

                result[dim] = DimensionBreakdown(
                    activity: blendedActivity,
                    satisfaction: sat,
                    consistency: blendedConsistency
                )
            } else {
                // No data yet — start at neutral 5/10 so compass looks balanced, not empty
                result[dim] = DimensionBreakdown(activity: 5, satisfaction: 5, consistency: 5)
            }
        }
        // Cache the result
        cachedBreakdowns = result
        cachedBreakdownsWeekStart = start
        cacheTimestamp = Date()

        return result
    }

    /// Balance Score (0-10): blend of arithmetic and geometric mean. The
    /// geometric mean naturally rewards breadth (drops faster when any dim
    /// is near zero), so no hand-tuned stdev penalty is needed.
    /// V3: replaced `mean − 1.5·stdev` (which could collapse to near-zero
    /// for legitimately-weak-in-one-area users) with this gentler blend.
    func balanceScore(for weekStart: Date? = nil) -> Double {
        let scores = weeklyScores(for: weekStart)
        let values = LifeDimension.scored.map { scores[$0] ?? 0 }
        guard !values.isEmpty else { return 0 }

        let mean = values.reduce(0, +) / Double(values.count)
        // +0.1 prevents a single zero dim from zeroing the entire product.
        let product = values.reduce(1.0) { $0 * ($1 + 0.1) }
        let geom = pow(product, 1.0 / Double(values.count))

        return max(0, min(10, 0.7 * mean + 0.3 * geom))
    }

    /// Harmony Score (30-100, for display). Floor + gentle power curve so
    /// users never see a punishingly-low number. At raw=0 the score is 30
    /// ("you're here"); at raw=10 it's 100. The 0.75 exponent keeps quick
    /// early gains while leaving Radiant (90+) genuinely earned.
    /// V3: replaced linear raw×10 with `30 + 70·(raw/10)^0.75`.
    func harmonyScore(for weekStart: Date? = nil) -> Int {
        let raw = balanceScore(for: weekStart)
        let display = 30.0 + 70.0 * pow(raw / 10.0, 0.75)
        return Int(display.rounded())
    }

    /// The stage that corresponds to the current display score.
    /// Used for color + label + coach copy on Home and Compass.
    func harmonyStage(for weekStart: Date? = nil) -> HarmonyStage {
        HarmonyStage.from(display: harmonyScore(for: weekStart))
    }

    // MARK: - V3 Today-Fill (Home momentum surface)

    /// "Today" starts at 4 AM local so early-morning completions attach to
    /// the same day the user was in the night before. Returns the most
    /// recent 4 AM local at or before `now`.
    /// Computed on-the-fly — no snapshot persistence. Travel across time
    /// zones is handled naturally: "today" re-derives from device-local
    /// calendar + current timezone on every call.
    func sessionDayStart(_ now: Date = Date()) -> Date {
        let cal = Calendar.current
        guard let todayFourAM = cal.date(
            bySettingHour: 4, minute: 0, second: 0, of: now
        ) else { return cal.startOfDay(for: now) }
        return now < todayFourAM
            ? cal.date(byAdding: .day, value: -1, to: todayFourAM) ?? todayFourAM
            : todayFourAM
    }

    /// Effort points this dim has accumulated since the most recent 4 AM.
    /// Multi-dim tasks split their effort evenly across tagged scored dims
    /// (matches activitySignal's split convention).
    func todayPoints(for dim: LifeDimension) -> Double {
        let start = sessionDayStart()
        let end = Date()
        return pointsInWindow(start: start, end: end)[dim] ?? 0
    }

    /// Target effort points per dimension per day. Defaults to
    /// `personalTarget() / 5` (weekdays-only pacing so rest days don't
    /// feel like falling behind), floored at 4 pts so a single moderate
    /// task (2 pts) or habit completion (2 pts) reads as partial progress
    /// (~50%) rather than instant-100%. With the prior floor of 1, the
    /// default 10-pt weekly target produced a 2-pt daily target and any
    /// single completion maxed the bar in one tap — defeating the whole
    /// "fill across the day" narrative the card is selling.
    func dailyTarget(for dim: LifeDimension) -> Double {
        let weekly = personalTarget(for: dim)
        return Double(max(4, Int((Double(weekly) / 5.0).rounded())))
    }

    /// Normalized today's fill for a dimension, 0.0–1.0+. Values >1.0 mean
    /// the user has exceeded the daily target; the card renders `+` and a
    /// stacking glow for each extra completion.
    func todayFill(for dim: LifeDimension) -> Double {
        todayPoints(for: dim) / dailyTarget(for: dim)
    }

    /// Reference value for the "yesterday tick" notch on the bar. Returns
    /// the most recent *active* day in the past 7 days (as a fraction of
    /// daily target). Suppresses the tick (returns nil) when nothing in
    /// the past week has activity — signals a "welcome back" empty state
    /// instead of a visible-but-zero notch.
    /// V3 rule: last-active-day-within-7, not literally yesterday. Keeps
    /// the reference fresh without weeks-stale data inflating expectations.
    func yesterdayTickValue(for dim: LifeDimension) -> Double? {
        let cal = Calendar.current
        let now = Date()
        let todayStart = sessionDayStart(now)
        for daysBack in 1...7 {
            guard let dayStart = cal.date(byAdding: .day, value: -daysBack, to: todayStart),
                  let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            let points = pointsInWindow(start: dayStart, end: dayEnd)[dim] ?? 0
            if points > 0 {
                return points / dailyTarget(for: dim)
            }
        }
        return nil
    }

    /// Shared point-sum helper used by `todayPoints` and `yesterdayTickValue`.
    /// Aggregates both task and habit completions in [start, end), summing
    /// effort per scored dim with multi-dim contributions split evenly.
    /// Excludes unscored (practical) dims.
    private func pointsInWindow(start: Date, end: Date) -> [LifeDimension: Double] {
        // Fetch by done-flag in SQL, then range-filter completedAt in Swift.
        // `#Predicate` can't express an optional Date comparison without
        // either a force-unwrap (crash-safe inside #Predicate but banned by
        // style rules) or a NilCoalesce expression that's rejected by the
        // predicate compiler. Filtering a small done-set in Swift is fine.
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in task.done == true }
        )
        let rawTasks = (try? modelContext.fetch(descriptor)) ?? []
        let tasks = rawTasks.filter { task in
            guard let completed = task.completedAt else { return false }
            return completed >= start && completed < end
        }
        var points: [LifeDimension: Double] = [:]
        for dim in LifeDimension.scored { points[dim] = 0 }
        for task in tasks {
            let scored = task.dimensions.filter(\.isScored)
            guard !scored.isEmpty else { continue }
            let split = Double(task.effort.points) / Double(scored.count)
            for dim in scored {
                points[dim, default: 0] += split
            }
        }

        // Habits contribute `HabitManager.habitEffortPoints` per completion,
        // split across scored dims. Without this, toggling a habit pulsed
        // the bus (particle flash) but never raised the bar height — the
        // bar reads today's fill from this helper.
        //
        // Habit completions are stored as `yyyy-MM-dd` day keys, so we match
        // by calendar day rather than timestamp: the session day starts at
        // 4 AM but a habit key for "today" parses to 00:00, which would
        // otherwise be excluded by a strict `date >= start` check.
        let habitDescriptor = FetchDescriptor<HabitItem>(
            predicate: #Predicate { $0.archivedAt == nil }
        )
        let habits = (try? modelContext.fetch(habitDescriptor)) ?? []
        let cal = Calendar.current
        let df = Self.habitDateKeyFormatter
        var dayKeys: Set<String> = []
        var cursor = cal.startOfDay(for: start)
        while cursor < end {
            dayKeys.insert(df.string(from: cursor))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        for habit in habits {
            let scored = habit.dimensions.filter(\.isScored)
            guard !scored.isEmpty else { continue }
            let overlap = habit.completionDates.intersection(dayKeys)
            guard !overlap.isEmpty else { continue }
            let split = Double(HabitManager.habitEffortPoints) / Double(scored.count)
            for _ in overlap {
                for dim in scored {
                    points[dim, default: 0] += split
                }
            }
        }
        return points
    }

    // MARK: - Signal 1: Activity (Effort-Weighted)

    /// Activity Score (0-10) per dimension.
    /// weekly_effort_points / personal_target * 10, capped at 10.
    private func activitySignal(from start: Date, to end: Date) -> [LifeDimension: Double] {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= start && $0.date < end && $0.done == true }
        )
        let tasks = (try? modelContext.fetch(descriptor)) ?? []

        var effortPoints: [LifeDimension: Double] = [:]
        for dim in LifeDimension.scored { effortPoints[dim] = 0 }

        for task in tasks {
            let scored = task.dimensions.filter(\.isScored)
            guard !scored.isEmpty else { continue }
            let splitPoints = Double(task.effort.points) / Double(scored.count)
            for dim in scored {
                effortPoints[dim, default: 0] += splitPoints
            }
        }

        let target = personalTarget()
        var scores: [LifeDimension: Double] = [:]
        for dim in LifeDimension.scored {
            scores[dim] = min(10, (effortPoints[dim] ?? 0) / Double(target) * 10)
        }
        return scores
    }

    /// Activity signal from pre-fetched tasks (avoids duplicate query).
    /// Multi-dimension tasks split their effort points evenly across tagged dimensions.
    private func activitySignalFromTasks(_ tasks: [TaskItem]) -> [LifeDimension: Double] {
        var effortPoints: [LifeDimension: Double] = [:]
        for dim in LifeDimension.scored { effortPoints[dim] = 0 }
        for task in tasks {
            let scored = task.dimensions.filter(\.isScored)
            guard !scored.isEmpty else { continue }
            let splitPoints = Double(task.effort.points) / Double(scored.count)
            for dim in scored {
                effortPoints[dim, default: 0] += splitPoints
            }
        }
        var scores: [LifeDimension: Double] = [:]
        for dim in LifeDimension.scored {
            let target = personalTarget(for: dim)
            scores[dim] = min(10, (effortPoints[dim] ?? 0) / Double(target) * 10)
        }
        return scores
    }

    // MARK: - Habit Contributions

    /// A single habit completion within the scoring window. Carries the
    /// habit's dimensions + the date it was completed on, so downstream
    /// helpers don't re-parse the completionDatesRaw string.
    private struct HabitCompletion {
        let dimensions: [LifeDimension]
        let date: Date
    }

    private static let habitDateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        // Pin locale/calendar so this key round-trips the same value on
        // non-Gregorian device calendars (e.g. Japanese era) and on locales
        // that reformat "yyyy-MM-dd" differently.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    /// Decode each habit's completion-date strings and keep only the ones
    /// inside [start, end). Habits without scored dimensions are dropped
    /// upstream (same rule as tasks).
    private func habitCompletions(in habits: [HabitItem], from start: Date, to end: Date) -> [HabitCompletion] {
        let df = Self.habitDateKeyFormatter
        var result: [HabitCompletion] = []
        for habit in habits {
            let scored = habit.dimensions.filter(\.isScored)
            guard !scored.isEmpty else { continue }
            for key in habit.completionDates {
                guard let date = df.date(from: key), date >= start, date < end else { continue }
                result.append(HabitCompletion(dimensions: scored, date: date))
            }
        }
        return result
    }

    /// Activity score contribution from habit completions. Each completion
    /// adds `HabitManager.habitEffortPoints` (2) to the tagged dimensions,
    /// split evenly across multi-tagged habits (mirrors task behavior).
    private func activitySignalFromHabits(_ completions: [HabitCompletion]) -> [LifeDimension: Double] {
        var effortPoints: [LifeDimension: Double] = [:]
        for dim in LifeDimension.scored { effortPoints[dim] = 0 }
        for completion in completions {
            let split = Double(HabitManager.habitEffortPoints) / Double(completion.dimensions.count)
            for dim in completion.dimensions {
                effortPoints[dim, default: 0] += split
            }
        }
        var scores: [LifeDimension: Double] = [:]
        for dim in LifeDimension.scored {
            let target = personalTarget(for: dim)
            scores[dim] = (effortPoints[dim] ?? 0) / Double(target) * 10
        }
        return scores
    }

    /// Set of weekday indices (1=Sun … 7=Sat) that each dimension was active
    /// on via habit completions. Used as an alternate consistency signal.
    private func habitActiveDays(_ completions: [HabitCompletion]) -> [LifeDimension: Set<Int>] {
        let cal = Calendar.current
        var days: [LifeDimension: Set<Int>] = [:]
        for dim in LifeDimension.scored { days[dim] = [] }
        for completion in completions {
            let weekday = cal.component(.weekday, from: completion.date)
            for dim in completion.dimensions {
                days[dim, default: []].insert(weekday)
            }
        }
        return days
    }

    /// Consistency signal from pre-fetched tasks (avoids duplicate query).
    /// Multi-dimension tasks count as an active day for each tagged dimension.
    private func consistencySignalFromTasks(_ tasks: [TaskItem]) -> [LifeDimension: Double] {
        let calendar = Calendar.current
        var activeDays: [LifeDimension: Set<Int>] = [:]
        for dim in LifeDimension.scored { activeDays[dim] = [] }
        for task in tasks {
            let scored = task.dimensions.filter(\.isScored)
            let dayOfWeek = calendar.component(.weekday, from: task.date)
            for dim in scored {
                activeDays[dim, default: []].insert(dayOfWeek)
            }
        }
        var scores: [LifeDimension: Double] = [:]
        for dim in LifeDimension.scored {
            scores[dim] = Double(activeDays[dim]?.count ?? 0) / 7.0 * 10
        }
        return scores
    }

    // MARK: - Signal 2: Satisfaction (Self-Reported)

    /// Satisfaction Score (0-10) per dimension.
    /// Handles two rating scales:
    ///   - Daily check-ins: 1-5 → normalized to 0-10 via `rating / 5.0 * 10`
    ///   - Onboarding quick-rate: 1-9 → normalized to 0-10 via `rating / 9.0 * 10`
    /// The normalizer auto-detects: if max rating in the set is > 5, use 9-scale.
    private func satisfactionSignal(from start: Date, to end: Date) -> [LifeDimension: Double] {
        let descriptor = FetchDescriptor<DailyBalanceCheckIn>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        let checkIns = (try? modelContext.fetch(descriptor)) ?? []

        // Collect normalized ratings (0-10) per dimension.
        // Determine scale per check-in record by looking at ALL dimension ratings
        // in that record — if ANY dimension > 5, the entire record is 1-9 scale
        // (onboarding). This prevents a dimension rated 5 on a 1-9 scale from
        // being misinterpreted as 5/5 = 10.0.
        var normalizedRatings: [LifeDimension: [Double]] = [:]
        for dim in LifeDimension.scored { normalizedRatings[dim] = [] }

        for checkIn in checkIns {
            // Determine scale for this entire check-in record
            var allRatingsInRecord: [Int] = []
            for dim in LifeDimension.scored {
                if let r = checkIn.satisfaction(for: dim) { allRatingsInRecord.append(r) }
            }
            let maxInRecord = allRatingsInRecord.max() ?? 5
            let scale = Double(maxInRecord > 5 ? 9 : 5)

            for dim in LifeDimension.scored {
                if let rating = checkIn.satisfaction(for: dim) {
                    normalizedRatings[dim, default: []].append(min(10, Double(rating) / scale * 10))
                }
            }
        }

        var scores: [LifeDimension: Double] = [:]
        for dim in LifeDimension.scored {
            let dimRatings = normalizedRatings[dim] ?? []
            if dimRatings.isEmpty {
                scores[dim] = 5 // neutral default — no data shouldn't penalize
            } else {
                scores[dim] = dimRatings.reduce(0, +) / Double(dimRatings.count)
            }
        }
        return scores
    }

    // MARK: - Signal 3: Consistency (Active Days)

    /// Consistency Score (0-10) per dimension.
    /// active_days_this_week / 7 * 10
    private func consistencySignal(from start: Date, to end: Date) -> [LifeDimension: Double] {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= start && $0.date < end && $0.done == true }
        )
        let tasks = (try? modelContext.fetch(descriptor)) ?? []
        let calendar = Calendar.current

        var activeDays: [LifeDimension: Set<Int>] = [:]
        for dim in LifeDimension.scored { activeDays[dim] = [] }

        for task in tasks {
            let scored = task.dimensions.filter(\.isScored)
            let dayOfWeek = calendar.component(.weekday, from: task.date)
            for dim in scored {
                activeDays[dim, default: []].insert(dayOfWeek)
            }
        }

        var scores: [LifeDimension: Double] = [:]
        for dim in LifeDimension.scored {
            let days = activeDays[dim]?.count ?? 0
            scores[dim] = Double(days) / 7.0 * 10
        }
        return scores
    }

    // MARK: - Personal Target

    /// The user's weekly effort point target per dimension. Stored in UserDefaults.
    func personalTarget(for dimension: LifeDimension? = nil) -> Int {
        if let dim = dimension {
            let key = "balanceTarget_\(dim.rawValue)"
            let stored = UserDefaults.standard.integer(forKey: key)
            return stored > 0 ? stored : Self.defaultTarget
        }
        return Self.defaultTarget
    }

    func setPersonalTarget(_ target: Int, for dimension: LifeDimension) {
        UserDefaults.standard.set(max(1, target), forKey: "balanceTarget_\(dimension.rawValue)")
    }

    // MARK: - Balance Streak

    /// Whether there is any real user data (tasks, habits, or check-ins) in
    /// the given week. Habits count as real data when at least one completion
    /// lands in the window.
    func hasRealData(for weekStart: Date? = nil) -> Bool {
        let calendar = Calendar.current
        let start = weekStart ?? calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let end = calendar.safeDate(byAdding: .day, value: 7, to: start)

        let taskDesc = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= start && $0.date < end && $0.done == true }
        )
        let taskCount = (try? modelContext.fetchCount(taskDesc)) ?? 0
        if taskCount > 0 { return true }

        let habitDesc = FetchDescriptor<HabitItem>(
            predicate: #Predicate { $0.archivedAt == nil }
        )
        let habits = (try? modelContext.fetch(habitDesc)) ?? []
        if !habitCompletions(in: habits, from: start, to: end).isEmpty { return true }

        let checkInDesc = FetchDescriptor<DailyBalanceCheckIn>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        let checkInCount = (try? modelContext.fetchCount(checkInDesc)) ?? 0
        return checkInCount > 0
    }

    /// Consecutive weeks where all 4 dimensions scored >= 3.0 out of 10 (with real data).
    func balanceStreak() -> Int {
        let calendar = Calendar.current
        let floor = 3.0
        var streak = 0
        var weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()

        for _ in 0..<52 {
            let scores = weeklyScores(for: weekStart)
            let allAboveFloor = LifeDimension.scored.allSatisfy { (scores[$0] ?? 0) >= floor }
            let hasData = hasRealData(for: weekStart)
            let isCurrentWeek = calendar.isDate(weekStart, equalTo: Date(), toGranularity: .weekOfYear)

            if isCurrentWeek {
                if hasData && allAboveFloor { streak += 1 }
                else if !hasData { /* skip, don't break */ }
                else { break }
            } else if !hasData {
                break
            } else if allAboveFloor {
                streak += 1
            } else {
                break
            }
            weekStart = calendar.safeDate(byAdding: .day, value: -7, to: weekStart)
        }
        return streak
    }

    // MARK: - Check-In Management

    /// Record satisfaction ratings for all dimensions at once during a check-in.
    func recordSatisfaction(ratings: [LifeDimension: Int], energyRating: Int? = nil) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.safeDate(byAdding: .day, value: 1, to: today)

        // Find or create today's check-in. Range predicate (not `== today`)
        // tolerates sub-second drift that can sneak in through CloudKit
        // round-trips, Watch sync, or any path that doesn't pin the date to
        // exact midnight — without it we were inserting duplicate rows.
        let descriptor = FetchDescriptor<DailyBalanceCheckIn>(
            predicate: #Predicate { $0.date >= today && $0.date < tomorrow }
        )
        let existing = try? modelContext.fetch(descriptor).first

        let checkIn = existing ?? DailyBalanceCheckIn(date: today)
        if existing == nil {
            modelContext.insert(checkIn)
        }

        for (dim, rating) in ratings {
            checkIn.setSatisfaction(max(1, min(5, rating)), for: dim)
        }
        if let energy = energyRating {
            checkIn.energyRating = energy
        }

        // Set the "best energy" dimension to the one with highest rating
        if let best = ratings.max(by: { $0.value < $1.value }) {
            checkIn.dimension = best.key
        }

        modelContext.safeSave()
    }

    /// Legacy: Record a single-dimension check-in (backwards compatible).
    func recordCheckIn(dimension: LifeDimension, energyRating: Int? = nil) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.safeDate(byAdding: .day, value: 1, to: today)
        let descriptor = FetchDescriptor<DailyBalanceCheckIn>(
            predicate: #Predicate { $0.date >= today && $0.date < tomorrow }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
        let checkIn = DailyBalanceCheckIn(dimension: dimension, energyRating: energyRating)
        modelContext.insert(checkIn)
        modelContext.safeSave()
    }

    /// Whether the user has completed today's balance check-in.
    func hasCheckedInToday() -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.safeDate(byAdding: .day, value: 1, to: today)
        let descriptor = FetchDescriptor<DailyBalanceCheckIn>(
            predicate: #Predicate { $0.date >= today && $0.date < tomorrow }
        )
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Today's satisfaction ratings, if any.
    func todaySatisfaction() -> [LifeDimension: Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.safeDate(byAdding: .day, value: 1, to: today)
        let descriptor = FetchDescriptor<DailyBalanceCheckIn>(
            predicate: #Predicate { $0.date >= today && $0.date < tomorrow }
        )
        guard let checkIn = try? modelContext.fetch(descriptor).first else { return [:] }
        var result: [LifeDimension: Int] = [:]
        for dim in LifeDimension.scored {
            if let rating = checkIn.satisfaction(for: dim) {
                result[dim] = rating
            }
        }
        return result
    }

    /// Average energy rating for the current week (-3 to +3), or nil if no ratings.
    func weeklyEnergyAverage() -> Double? {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let end = calendar.safeDate(byAdding: .day, value: 7, to: start)
        let descriptor = FetchDescriptor<DailyBalanceCheckIn>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        let checkIns = (try? modelContext.fetch(descriptor)) ?? []
        let rated = checkIns.compactMap(\.energyRating)
        guard !rated.isEmpty else { return nil }
        return Double(rated.reduce(0, +)) / Double(rated.count)
    }

    // MARK: - Task Counts (for display)

    /// Returns effort-weighted points per dimension this week (split across multi-tagged tasks).
    func thisWeekEffortPoints() -> [LifeDimension: Int] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let end = calendar.safeDate(byAdding: .day, value: 7, to: start)
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= start && $0.date < end && $0.done == true }
        )
        let tasks = (try? modelContext.fetch(descriptor)) ?? []
        var points: [LifeDimension: Double] = [:]
        for dim in LifeDimension.scored { points[dim] = 0 }
        for task in tasks {
            let scored = task.dimensions.filter(\.isScored)
            guard !scored.isEmpty else { continue }
            let split = Double(task.effort.points) / Double(scored.count)
            for dim in scored {
                points[dim, default: 0] += split
            }
        }
        return points.mapValues { Int($0.rounded()) }
    }

    /// Returns completed task count per dimension this week.
    /// Multi-tagged tasks count toward each tagged dimension.
    func thisWeekTaskCounts() -> [LifeDimension: Int] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let end = calendar.safeDate(byAdding: .day, value: 7, to: start)
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= start && $0.date < end && $0.done == true }
        )
        let tasks = (try? modelContext.fetch(descriptor)) ?? []
        var counts: [LifeDimension: Int] = [:]
        for dim in LifeDimension.scored { counts[dim] = 0 }
        for task in tasks {
            for dim in task.dimensions where dim.isScored {
                counts[dim, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - Nudge System

    struct Nudge: Identifiable {
        let id = UUID()
        let dimension: LifeDimension
        let message: String
        let suggestion: String
        let signal: String  // which signal is weakest: "activity", "satisfaction", "consistency"
    }

    /// Returns a nudge for today based on the weakest signal across dimensions.
    func todayNudge() -> Nudge? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dismissKey = "nudgeDismissed_\(df.string(from: Date()))"
        if UserDefaults.standard.bool(forKey: dismissKey) { return nil }

        let breakdowns = weeklyBreakdowns()
        let seasonGoal = activeSeasonGoal()

        // Find the dimension with lowest composite score
        let defaultBD = DimensionBreakdown(activity: 0, satisfaction: 5, consistency: 0)
        var candidates = LifeDimension.scored.map { ($0, breakdowns[$0] ?? defaultBD) }
            .sorted { $0.1.composite < $1.1.composite }

        // Boost season goal priority if lagging
        if let goal = seasonGoal, let bd = breakdowns[goal.dimension], bd.composite < 5 {
            candidates.insert((goal.dimension, bd), at: 0)
            if let dup = candidates.dropFirst().firstIndex(where: { $0.0 == goal.dimension }) {
                candidates.remove(at: dup)
            }
        }

        guard let (weakest, breakdown) = candidates.first, breakdown.composite < 5 else { return nil }

        // Identify which signal is weakest
        let signals: [(String, Double)] = [
            ("activity", breakdown.activity),
            ("satisfaction", breakdown.satisfaction),
            ("consistency", breakdown.consistency)
        ]
        let weakestSignal = signals.min(by: { $0.1 < $1.1 })?.0 ?? "activity"

        let message: String
        switch weakestSignal {
        case "activity":
            message = "Your \(weakest.label) activity is low this week. A small effort counts!"
        case "satisfaction":
            message = "You've rated \(weakest.label) satisfaction low. What would help?"
        case "consistency":
            message = "Try adding a small \(weakest.label) activity each day for consistency."
        default:
            message = "Your \(weakest.label) could use some attention."
        }

        return Nudge(
            dimension: weakest,
            message: message,
            suggestion: nudgeSuggestion(for: weakest),
            signal: weakestSignal
        )
    }

    func dismissNudge() {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        UserDefaults.standard.set(true, forKey: "nudgeDismissed_\(df.string(from: Date()))")
    }

    private func nudgeSuggestion(for dimension: LifeDimension) -> String {
        switch dimension {
        case .physical:  return ["A 20-minute walk?", "Some stretching today?", "A quick workout?"].randomElement() ?? ""
        case .mental:    return ["Read for 15 minutes?", "Learn something new?", "Work on a creative project?"].randomElement() ?? ""
        case .emotional: return ["Call someone you care about?", "Plan some fun tonight?", "Do something social?"].randomElement() ?? ""
        case .spiritual: return ["A short meditation?", "Write in a gratitude journal?", "Spend time in nature?"].randomElement() ?? ""
        case .practical: return "Tackle a quick errand?"
        }
    }

    // MARK: - Season Goals

    func activeSeasonGoal() -> SeasonGoal? {
        // Use startOfDay to include the entire final day (matches SeasonGoal.isActive logic)
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<SeasonGoal>(
            predicate: #Predicate { $0.completedAt == nil && $0.endDate >= today },
            sortBy: [SortDescriptor(\SeasonGoal.startDate, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first
    }

    func startSeasonGoal(dimension: LifeDimension, intention: String) {
        if let existing = activeSeasonGoal() { existing.completedAt = Date() }
        let goal = SeasonGoal(dimension: dimension, intention: intention)
        modelContext.insert(goal)
        modelContext.safeSave()
    }

    func completeSeasonGoal() {
        if let goal = activeSeasonGoal() {
            goal.completedAt = Date()
            modelContext.safeSave()
        }
    }

    func seasonGoalProgress() -> Double? {
        guard let goal = activeSeasonGoal() else { return nil }
        let scores = weeklyScores()
        return scores[goal.dimension]
    }

    // MARK: - Smart Activity Recall

    /// A suggestion for an activity the user likely did today but didn't log.
    struct RecallSuggestion: Identifiable {
        let id = UUID()
        let pattern: ActivityPattern
        let message: String
    }

    /// Returns up to 2 recall suggestions for unlogged activities today.
    /// Only shows patterns with confidence > 60% that haven't been logged today.
    func recallSuggestions() -> [RecallSuggestion] {
        let descriptor = FetchDescriptor<ActivityPattern>()
        let patterns = (try? modelContext.fetch(descriptor)) ?? []
        guard !patterns.isEmpty else { return [] }

        // Find which activity names were already logged today
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayEnd = calendar.safeDate(byAdding: .day, value: 1, to: todayStart)
        let taskDescriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= todayStart && $0.date < todayEnd && $0.done == true }
        )
        let todayTasks = (try? modelContext.fetch(taskDescriptor)) ?? []
        let loggedNames = Set(todayTasks.map { $0.title.lowercased() })

        // Filter and rank patterns
        var candidates: [(ActivityPattern, Double)] = []
        for pattern in patterns {
            // Skip if already logged today
            // Word-boundary match: "running errands" should NOT suppress "run" pattern
            if loggedNames.contains(where: { name in
                name == pattern.activityName ||
                name.components(separatedBy: .whitespaces).contains(pattern.activityName)
            }) { continue }
            // Skip suppressed patterns
            if pattern.isSuppressed { continue }
            // Skip if already suggested today
            if let lastSuggested = pattern.lastSuggested,
               calendar.isDateInToday(lastSuggested) { continue }

            let confidence = pattern.confidenceForToday()
            if confidence > 0.6 {
                candidates.append((pattern, confidence))
            }
        }

        // Sort by confidence, take top 2
        candidates.sort { $0.1 > $1.1 }
        let top = candidates.prefix(2)

        return top.map { pattern, _ in
            let dayName = calendar.weekdaySymbols[calendar.component(.weekday, from: Date()) - 1]
            let message = "I noticed you usually do \(pattern.activityName) on \(dayName)s. Did you get to it today?"
            return RecallSuggestion(pattern: pattern, message: message)
        }
    }

    /// Record that the user confirmed doing a recalled activity.
    func acceptRecall(_ pattern: ActivityPattern, durationMinutes: Int) {
        // Update pattern stats
        pattern.totalSuggested += 1
        pattern.totalAccepted += 1
        pattern.consecutiveDismissals = 0
        pattern.lastSuggested = Date()
        pattern.lastConfirmed = Date()
        if durationMinutes > 0 {
            pattern.typicalDurationMinutes = durationMinutes
        }

        // Create a retroactive task
        let task = TaskItem(
            title: pattern.activityName.prefix(1).uppercased() + pattern.activityName.dropFirst(),
            category: .personal,
            priority: .low,
            date: Date(),
            icon: pattern.dimension.icon.contains("figure") ? "🏃" : "✨",
            notes: "Recalled from evening check-in"
        )
        task.dimension = pattern.dimension
        modelContext.insert(task)
        task.done = true
        task.completedAt = Date()

        modelContext.safeSave()
    }

    /// Record that the user dismissed a recall suggestion.
    func dismissRecall(_ pattern: ActivityPattern) {
        pattern.totalSuggested += 1
        pattern.consecutiveDismissals += 1
        pattern.lastSuggested = Date()
        modelContext.safeSave()
    }

    // MARK: - Pattern Learning (from completed tasks)

    /// Analyze completed tasks to detect and update activity patterns.
    /// Call this periodically (e.g., during evening check-in or daily background task).
    func updateActivityPatterns() {
        let calendar = Calendar.current
        let fourWeeksAgo = calendar.safeDate(byAdding: .day, value: -28, to: Date())
        let now = Date()

        // Fetch all completed dimension-tagged tasks from last 4 weeks
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= fourWeeksAgo && $0.date < now && $0.done == true }
        )
        let tasks = (try? modelContext.fetch(descriptor)) ?? []

        // Group by normalized title
        var activityOccurrences: [String: [(task: TaskItem, weekday: Int)]] = [:]
        for task in tasks {
            guard !task.dimensions.isEmpty else { continue }
            let key = task.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            let weekday = calendar.component(.weekday, from: task.date)
            activityOccurrences[key, default: []].append((task: task, weekday: weekday))
        }

        // Only create patterns for activities that occurred 3+ times in 4 weeks
        for (name, occurrences) in activityOccurrences where occurrences.count >= 3 {
            let patternDescriptor = FetchDescriptor<ActivityPattern>(
                predicate: #Predicate { $0.activityName == name }
            )
            let existing = try? modelContext.fetch(patternDescriptor).first

            let weekdays = occurrences.map(\.weekday)
            let uniqueWeekdays = Array(Set(weekdays)).sorted()
            let frequency = min(7, occurrences.count / 4 + 1) // approximate weekly frequency

            let dim = occurrences.last?.task.dimensions.first ?? .physical

            if let pattern = existing {
                // Update existing pattern
                pattern.weekdayPattern = uniqueWeekdays
                pattern.weeklyFrequency = frequency
                pattern.dimension = dim
            } else {
                // Create new pattern
                let pattern = ActivityPattern(
                    activityName: name,
                    dimension: dim,
                    typicalDurationMinutes: 30,
                    weekdayPattern: uniqueWeekdays,
                    weeklyFrequency: frequency
                )
                modelContext.insert(pattern)
            }
        }

        modelContext.safeSave()
    }

    // MARK: - Weekly Reflection

    func weeklyReflectionPrompt() -> String? {
        let breakdowns = weeklyBreakdowns()
        let hasData = breakdowns.values.contains(where: { $0.composite > 0 })
        guard hasData else { return nil }

        let sorted = LifeDimension.scored.sorted { (breakdowns[$0]?.composite ?? 0) > (breakdowns[$1]?.composite ?? 0) }
        guard let strongest = sorted.first, let weakest = sorted.last else { return nil }

        let strongScore = breakdowns[strongest]?.composite ?? 0
        let weakScore = breakdowns[weakest]?.composite ?? 0

        if strongScore > 6 && weakScore < 3 {
            return "Your \(strongest.label) was strong this week, but \(weakest.label) fell behind. What would help balance them?"
        } else if strongScore > 7 {
            return "Great \(strongest.label) week! What made that happen?"
        } else if weakScore < 2 {
            return "\(weakest.label) was quiet this week. Is that intentional, or would you like to shift?"
        } else {
            return "How balanced did this week feel across your life dimensions?"
        }
    }

    private func weeklyReflectionKey() -> String {
        let cal = Calendar.current
        return "weeklyReflection_\(cal.component(.weekOfYear, from: Date()))_\(cal.component(.yearForWeekOfYear, from: Date()))"
    }

    func saveWeeklyReflection(_ text: String) {
        let key = weeklyReflectionKey()
        UserDefaults.standard.set(true, forKey: key)
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UserDefaults.standard.set(text, forKey: key + "_text")
        }
    }

    func loadWeeklyReflectionText() -> String? {
        UserDefaults.standard.string(forKey: weeklyReflectionKey() + "_text")
    }

    func hasReflectedThisWeek() -> Bool {
        UserDefaults.standard.bool(forKey: weeklyReflectionKey())
    }

    // MARK: - AI Context

    func balanceSummaryForAI() -> String {
        let breakdowns = weeklyBreakdowns()
        let balance = balanceScore()
        let display = harmonyScore()
        let stage = harmonyStage()
        let points = thisWeekEffortPoints()
        let streak = balanceStreak()
        let seasonGoal = activeSeasonGoal()

        var lines: [String] = []
        // V3: send BOTH the raw 0–10 balance (for the model to reason about)
        // AND the display score + stage (so AI messages match what the user
        // sees in the UI — otherwise the model says "your balance is 5.2"
        // while the UI shows "Thriving 77" and the two narratives contradict).
        lines.append("Life Compass this week: UI shows \"\(stage.label) \(display)\" (display 30–100, floored + curved). Raw balance: \(String(format: "%.1f", balance))/10.")

        for dim in LifeDimension.scored {
            let bd = breakdowns[dim] ?? DimensionBreakdown(activity: 0, satisfaction: 5, consistency: 0)
            let pts = points[dim] ?? 0
            lines.append("  \(dim.label): \(String(format: "%.1f", bd.composite))/10 (activity:\(String(format: "%.1f", bd.activity)) satisfaction:\(String(format: "%.1f", bd.satisfaction)) consistency:\(String(format: "%.1f", bd.consistency)), \(pts) effort points)")
        }

        if streak > 0 { lines.append("Balance streak: \(streak) weeks") }

        if let goal = seasonGoal {
            lines.append("Season goal: Focus on \(goal.dimension.label) (\(goal.daysRemaining) days left)")
            if !goal.intention.isEmpty { lines.append("  Intention: \(goal.intention)") }
        }

        // Energy data
        if let energy = weeklyEnergyAverage() {
            lines.append("Average daily energy this week: \(String(format: "%.1f", energy)) (-3 to +3 scale)")
        }

        // Energy trend (last 4 weeks)
        let trends = energyTrend()
        if !trends.isEmpty {
            let trendStr = trends.map { "wk\($0.weekOffset): \(String(format: "%.1f", $0.average))" }.joined(separator: ", ")
            lines.append("Energy trend (recent→oldest): \(trendStr)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Energy Insights (Phase 3)

    struct WeekEnergy {
        let weekOffset: Int // 0 = current week, 1 = last week, etc.
        let average: Double
    }

    /// Returns average energy per week for the last 4 weeks.
    func energyTrend() -> [WeekEnergy] {
        let calendar = Calendar.current
        var results: [WeekEnergy] = []

        for offset in 0..<4 {
            let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset,
                to: calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()) ?? Date()
            let weekEnd = calendar.safeDate(byAdding: .day, value: 7, to: weekStart)

            let descriptor = FetchDescriptor<DailyBalanceCheckIn>(
                predicate: #Predicate { $0.date >= weekStart && $0.date < weekEnd }
            )
            let checkIns = (try? modelContext.fetch(descriptor)) ?? []
            let rated = checkIns.compactMap(\.energyRating)
            if !rated.isEmpty {
                let avg = Double(rated.reduce(0, +)) / Double(rated.count)
                results.append(WeekEnergy(weekOffset: offset, average: avg))
            }
        }
        return results
    }

    /// Generates human-readable energy insights if enough data exists (4+ weeks).
    func energyInsights() -> String? {
        let trends = energyTrend()
        guard trends.count >= 3 else { return nil } // Need at least 3 weeks

        let current = trends.first(where: { $0.weekOffset == 0 })?.average
        let lastWeek = trends.first(where: { $0.weekOffset == 1 })?.average
        let overall = trends.map(\.average).reduce(0, +) / Double(trends.count)

        var insights: [String] = []

        // Trend direction
        if let curr = current, let last = lastWeek {
            if curr > last + 0.5 {
                insights.append("Your energy is trending up this week — nice momentum.")
            } else if curr < last - 0.5 {
                insights.append("Energy dipped this week compared to last. Consider what changed.")
            } else {
                insights.append("Energy is holding steady.")
            }
        }

        // Overall level
        if overall > 1.5 {
            insights.append("Your average energy has been strong. Keep doing what's working.")
        } else if overall < -0.5 {
            insights.append("Energy has been low recently. Small wins and rest might help.")
        }

        return insights.isEmpty ? nil : insights.joined(separator: " ")
    }
}
