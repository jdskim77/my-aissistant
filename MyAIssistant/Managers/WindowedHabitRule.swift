import Foundation

/// Fires mid-window for a habit that has a `timeWindow` set, is currently
/// in-window, past the window's midpoint, and still not completed today.
/// The intent is to give the user a chance to act *while the window is
/// open* — before the day is lost and the `habitSlip` category takes
/// over (see TIME_WINDOW_HABITS_PLAN.md §2).
///
/// **One nudge per evaluation pass, one nudge per habit per day.**
/// Multiple habits can be active simultaneously (e.g., three morning
/// habits at 9:30am). The rule picks the habit with the highest current
/// streak — loss aversion is a stronger motivator than gain — and
/// breaks ties by alphabetical title sort for determinism.
/// Per-habit-per-day dedupe comes from `context.nudgedHabitIDsToday`
/// (populated by NudgeEngine from today's windowedHabit nudges).
///
/// **Why not entangle with `habitSlip`.** `habitSlip` is a
/// multi-day-miss signal, not a within-window signal. They can compete
/// when a habit has been missed *and* is currently in-window; the
/// engine's rule order (this rule FIRST among windowed rules) keeps
/// the gentler "still open" framing ahead of the sharper slip framing
/// while the window is live. When `habitSlip` ships and wires a live
/// rule, put it *after* this one in `NudgeEngine.rules` so the kind
/// ask leads.
struct WindowedHabitRule: NudgeTriggerRule {
    let id: NudgeCategory = .windowedHabit

    var cooldown: TimeInterval {
        Double(AppConstants.nudgeWindowedHabitCooldownHours) * 3600
    }

    /// A user's `.night` habit overlaps the default quiet-hours window
    /// (21..8) almost entirely. Respecting quiet hours for this rule
    /// would silently dead-class every night nudge — the user
    /// explicitly set a night window, so surfacing an in-app pinned
    /// card during those hours is consistent with their intent. We
    /// still respect quiet hours for scheduled (BGTask) triggers so we
    /// don't wake the device at midnight; only foreground in-app
    /// delivery bypasses. QA BUG-QA-02.
    var bypassesQuietHoursWhenForeground: Bool { true }

    func evaluate(context: NudgeEvalContext) -> NudgeCandidate? {
        // 1. Filter out habits already nudged today. Per-habit-per-day
        //    dedupe — the engine's category cooldown is belt-and-
        //    suspenders but doesn't track per-habit granularity.
        let eligible = context.activeWindowedHabits.filter {
            !context.nudgedHabitIDsToday.contains($0.habitID)
        }

        guard let pick = Self.selectHabit(
            from: eligible,
            recentlyNudged: context.nudgedHabitIDsRecent
        ) else { return nil }

        // 2. Compose params + trigger context. `habitID` goes into
        //    triggerContext so the engine's `fetchNudgedHabitIDsToday`
        //    helper can see it on subsequent passes. `habitTitle` goes
        //    into templateParams for NudgeComposer interpolation.
        let templateParams: [String: String] = [
            "habitTitle": pick.title
        ]
        let triggerContext: [String: String] = [
            "habitID": pick.habitID,
            "window": pick.window.rawValue,
            "currentStreak": String(pick.currentStreak)
        ]

        return NudgeCandidate(
            category: .windowedHabit,
            // Intentionally nil — windowed-habit nudges target a specific
            // habit, not a dimension. Passing a dimension here would make
            // the engine's per-dimension cooldown (48h) block a legitimate
            // habit nudge the next day because some unrelated
            // weak-dimension nudge happened yesterday in the same tag.
            dimension: nil,
            suggestedAction: .openHabit,
            actionPayload: pick.habitID,
            templateParams: templateParams,
            triggerContext: triggerContext
        )
    }

    // MARK: - Selection

    /// Pick the habit to nudge about. Two-tier selection:
    ///
    /// 1. **Starvation guard.** If any eligible habit has NOT been
    ///    nudged in the last 7 days (`recentlyNudged`), restrict the
    ///    pool to those habits — a never-nudged zero-streak habit
    ///    beats a frequently-nudged long-streak habit. Prevents a
    ///    single long-streak habit from monopolizing the nudge slot
    ///    and starving Hesse-never-gets-picked zero-streak habits
    ///    (UX audit §4).
    /// 2. **Within the chosen pool.** Highest `currentStreak` wins
    ///    (loss aversion), alphabetical title breaks ties
    ///    deterministically.
    ///
    /// `recentlyNudged` is the full 7-day set including *today's*
    /// nudges. The `evaluate(context:)` filter has already removed
    /// today's habits, so the pool here is always "eligible for a
    /// fresh nudge" — the recent set is only consulted to decide
    /// tier 1 vs tier 2. Pure function; exposed for unit tests.
    static func selectHabit(
        from eligible: [WindowedHabitSnapshot],
        recentlyNudged: Set<String>
    ) -> WindowedHabitSnapshot? {
        guard !eligible.isEmpty else { return nil }
        let starved = eligible.filter { !recentlyNudged.contains($0.habitID) }
        let pool = starved.isEmpty ? eligible : starved
        return pool.max { a, b in
            if a.currentStreak != b.currentStreak {
                return a.currentStreak < b.currentStreak
            }
            return a.title > b.title
        }
    }
}
