import XCTest
import SwiftData
@testable import MyAIssistant

/// Zero-coverage critical path: `NudgeEngine` is the gate between every
/// proactive-coaching signal and an actual notification/banner reaching the
/// user. A silent regression here (kill switch inverted, quiet hours not
/// respected, a dedupe check broken, the crisis/safety pause not sticking)
/// either spams a user who asked to be left alone or — worse — re-surfaces
/// or fails to suppress safety-route content. None of these failure modes
/// crash; they only show up as "the app did something it promised not to."
///
/// Covers: kill switch, quiet hours (incl. midnight wrap + foreground
/// bypass), frequency caps (daily + min-gap), rule/dimension cooldown,
/// silenced categories, dedupe of already-nudged check-ins/habits, the
/// safety pause window, `safetyNoteFingerprint` stability + one-emit-per-
/// fingerprint, and `evaluate()`'s re-entrancy guard.
@MainActor
final class NudgeEngineTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private var composer: NudgeComposer!

    override func setUp() async throws {
        container = try TestModelContainer.create()
        context = container.mainContext
        composer = NudgeComposer()
        // Isolated suite per test so nudge-tuning keys (kill switch,
        // quiet hours, silenced categories, safety fingerprints/pause)
        // never leak state between tests or read stale state from the
        // shared `.standard` suite.
        let suiteName = "NudgeEngineTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: defaults.suiteName ?? "")
        UserDefaults.standard.removeObject(forKey: AppConstants.nudgePostLowMoodEnabledKey)
        container = nil
        context = nil
        defaults = nil
        composer = nil
    }

    // MARK: - Fixture helpers

    private func makeEngine(
        now: @escaping () -> Date = { Self.fixedNow },
        killSwitchOverride: Bool? = false,
        rules: [NudgeTriggerRule] = [],
        crisisClassifier: CrisisClassifier = StubCrisisClassifier(result: .safe),
        enableNudges: Bool = true,
        frequency: NudgeFrequency = .balanced
    ) -> NudgeEngine {
        if enableNudges {
            defaults.set(true, forKey: AppConstants.nudgeEnabledKey)
        }
        defaults.set(frequency.rawValue, forKey: AppConstants.nudgeFrequencyKey)
        let engine = NudgeEngine(
            modelContext: context,
            composer: composer,
            crisisClassifier: crisisClassifier,
            now: now,
            defaults: defaults,
            killSwitchOverride: killSwitchOverride
        )
        engine.rules = rules
        return engine
    }

    /// Fixed reference instant: 2024-01-15 10:00:00 UTC (a Monday, clear of
    /// any quiet-hours default window) so tests that don't care about time
    /// get a deterministic, daylight hour.
    private static let fixedNow: Date = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2024, month: 1, day: 15, hour: 10))!
    }()

    private func dateAt(hour: Int, day: Int = 15) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2024, month: 1, day: day, hour: hour))!
    }

    private func allNudges() throws -> [Nudge] {
        try context.fetch(FetchDescriptor<Nudge>())
    }

    /// Always-fires stub rule — used wherever the test only cares about
    /// engine-level gating, not any specific rule's own preconditions.
    private struct AlwaysFireRule: NudgeTriggerRule {
        let id: NudgeCategory
        var cooldown: TimeInterval = 48 * 3600
        var bypassesQuietHoursWhenForeground: Bool = false
        var dimension: LifeDimension?

        func evaluate(context: NudgeEvalContext) -> NudgeCandidate? {
            NudgeCandidate(category: id, dimension: dimension)
        }
    }

    private struct StubCrisisClassifier: CrisisClassifier, Sendable {
        let result: CrisisEvaluation
        func evaluate(_ text: String) -> CrisisEvaluation { result }
    }

    /// Inserts an already-delivered `Nudge` directly, bypassing the engine,
    /// so cooldown/cap/dedupe tests can set up "history" deterministically.
    @discardableResult
    private func insertDeliveredNudge(
        category: NudgeCategory,
        dimension: LifeDimension? = nil,
        createdAt: Date,
        deliveredAt: Date? = nil,
        triggerContextJSON: String = "{}"
    ) -> Nudge {
        let nudge = Nudge(
            createdAt: createdAt,
            category: category,
            triggerContextJSON: triggerContextJSON,
            bodyText: "test",
            dimension: dimension,
            status: .delivered
        )
        nudge.deliveredAt = deliveredAt ?? createdAt
        context.insert(nudge)
        try? context.save()
        return nudge
    }

    // MARK: - Kill switch

    func testKillSwitchBlocksAllEvaluation() async throws {
        // If the `guard !(killSwitchOverride ?? ...)` line were removed,
        // this would fall through to the always-firing rule and persist a
        // nudge — this test fails without that guard.
        let engine = makeEngine(
            killSwitchOverride: true,
            rules: [AlwaysFireRule(id: .weakDimension)]
        )
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 0, "kill switch must block evaluation entirely")
    }

    func testKillSwitchOffAllowsEvaluation() async throws {
        let engine = makeEngine(
            killSwitchOverride: false,
            rules: [AlwaysFireRule(id: .weakDimension)]
        )
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 1, "kill switch disabled must let a matching rule fire")
    }

    // MARK: - User-facing enabled toggle + frequency

    func testNudgeDisabledTogglePreventsNudge() async throws {
        let engine = makeEngine(rules: [AlwaysFireRule(id: .weakDimension)], enableNudges: false)
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 0)
    }

    func testFrequencyOffPreventsNudge() async throws {
        let engine = makeEngine(rules: [AlwaysFireRule(id: .weakDimension)], frequency: .off)
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 0)
    }

    // MARK: - Quiet hours

    func testQuietHoursBlocksNonBypassingRuleDuringDefaultWindow() async throws {
        // Default quiet window is 21:00-08:00. 23:00 is inside it.
        // Verified by reasoning: `isQuietHours` computes
        // `hour >= startHour || hour < endHour` for a wrapped window
        // (21 > 8); hour=23 satisfies `hour >= 21`, so it is quiet. If the
        // per-rule quiet-hours `if quietNow { ... continue }` gate were
        // removed, this rule (bypass=false) would fire anyway.
        let engine = makeEngine(
            now: { self.dateAt(hour: 23) },
            rules: [AlwaysFireRule(id: .weakDimension, bypassesQuietHoursWhenForeground: false)]
        )
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 0, "quiet hours must block a non-bypassing rule")
    }

    func testQuietHoursWrapPastMidnightStillBlocksAt2AM() async throws {
        // 02:00 falls inside the wrapped 21..8 window via the `hour < endHour`
        // branch. If the wrap branch (`startHour > endHour`) were replaced
        // with a naive `hour >= startHour && hour < endHour`, 2 AM would
        // incorrectly read as NOT quiet (2 is neither >= 21 nor are both
        // true), and this rule would wrongly fire.
        let engine = makeEngine(
            now: { self.dateAt(hour: 2) },
            rules: [AlwaysFireRule(id: .weakDimension, bypassesQuietHoursWhenForeground: false)]
        )
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 0, "2am must be treated as quiet under the wrapped 21-8 window")
    }

    func testOutsideQuietHoursRuleFiresNormally() async throws {
        // 10am is outside the default 21-8 window — sanity check the
        // control case for the two quiet-hours tests above.
        let engine = makeEngine(
            now: { self.dateAt(hour: 10) },
            rules: [AlwaysFireRule(id: .weakDimension, bypassesQuietHoursWhenForeground: false)]
        )
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 1)
    }

    func testQuietHoursForegroundBypassAllowsRuleToFire() async throws {
        let engine = makeEngine(
            now: { self.dateAt(hour: 23) },
            rules: [AlwaysFireRule(id: .windowedHabit, bypassesQuietHoursWhenForeground: true)]
        )
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 1, "a rule opting in to foreground bypass must fire during quiet hours on foreground trigger")
    }

    func testQuietHoursBypassDoesNotApplyToScheduledTrigger() async throws {
        // Fix for QA BUG-QA-02: scheduled (BGTask) triggers must always
        // respect quiet hours even if the rule sets
        // `bypassesQuietHoursWhenForeground = true`, because that path can
        // wake the device with a push notification at 2am. If the
        // `trigger == .foreground` check were dropped from the bypass
        // condition, this would wrongly fire on a scheduled run too.
        let engine = makeEngine(
            now: { self.dateAt(hour: 23) },
            rules: [AlwaysFireRule(id: .windowedHabit, bypassesQuietHoursWhenForeground: true)]
        )
        _ = await engine.runScheduledEvaluation()
        XCTAssertEqual(try allNudges().count, 0, "foreground-only bypass must not apply to scheduled evaluation")
    }

    // MARK: - Frequency caps

    func testDailyCapBlocksAdditionalNudgeOnceReached() async throws {
        // Gentle frequency has a dailyCap of 1.
        insertDeliveredNudge(category: .weakDimension, createdAt: Self.fixedNow.addingTimeInterval(-3600 * 5))
        let engine = makeEngine(
            now: { Self.fixedNow },
            rules: [AlwaysFireRule(id: .streakAtRisk)],
            frequency: .gentle
        )
        await engine.evaluateOnForeground()
        // Still just the one we inserted manually — no second nudge.
        XCTAssertEqual(try allNudges().count, 1, "daily cap must block once the frequency's dailyCap is reached")
    }

    func testMinHoursBetweenBlocksEvenUnderDailyCap() async throws {
        // Balanced cap is 2/day (nudgeMaxPerDay), so a single prior delivery
        // today is well under the daily cap — but it's only 20 minutes old,
        // inside the 1-hour minimum gap (`nudgeMinHoursBetween`). If that
        // check were removed, this would fire a second nudge immediately.
        insertDeliveredNudge(category: .weakDimension, createdAt: Self.fixedNow.addingTimeInterval(-60 * 20))
        let engine = makeEngine(
            now: { Self.fixedNow },
            rules: [AlwaysFireRule(id: .streakAtRisk)],
            frequency: .balanced
        )
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 1, "min-gap-between-nudges must block a second delivery within the hour")
    }

    // MARK: - Rule / dimension cooldown

    func testRuleCooldownPreventsSameCategoryRefire() async throws {
        // AlwaysFireRule's default cooldown is 48h; deliver one 1h ago.
        insertDeliveredNudge(category: .weakDimension, createdAt: Self.fixedNow.addingTimeInterval(-3600))
        let engine = makeEngine(
            now: { Self.fixedNow },
            rules: [AlwaysFireRule(id: .weakDimension)]
        )
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 1, "rule must be in cooldown and not refire the same category")
    }

    func testDimensionCooldownBlocksCandidateSharingDimension() async throws {
        // nudgeMaxPerDimensionHours = 48. A delivered nudge tagged
        // `.physical` 1h ago should block a *different* category's
        // candidate that's also tagged `.physical`.
        insertDeliveredNudge(category: .habitSlip, dimension: .physical, createdAt: Self.fixedNow.addingTimeInterval(-3600))
        let engine = makeEngine(
            now: { Self.fixedNow },
            rules: [AlwaysFireRule(id: .weakDimension, dimension: .physical)]
        )
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 1, "dimension cooldown must block a candidate tagged with a recently-nudged dimension")
    }

    func testDimensionCooldownDoesNotBlockUnrelatedDimension() async throws {
        insertDeliveredNudge(category: .habitSlip, dimension: .physical, createdAt: Self.fixedNow.addingTimeInterval(-3600))
        let engine = makeEngine(
            now: { Self.fixedNow },
            rules: [AlwaysFireRule(id: .weakDimension, dimension: .mental)]
        )
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 2, "a different dimension must not be blocked by an unrelated dimension's cooldown")
    }

    // MARK: - Silenced categories

    func testSilencedCategorySkipsThatRuleButFallsThroughToNext() async throws {
        defaults.set(NudgeCategory.weakDimension.rawValue, forKey: AppConstants.nudgeSilencedCategoriesKey)
        let engine = makeEngine(
            rules: [AlwaysFireRule(id: .weakDimension), AlwaysFireRule(id: .streakAtRisk)]
        )
        await engine.evaluateOnForeground()
        let nudges = try allNudges()
        XCTAssertEqual(nudges.count, 1)
        XCTAssertEqual(nudges.first?.category, .streakAtRisk, "silenced category must be skipped in favor of the next rule")
    }

    // MARK: - Dedupe: check-ins (PostLowMoodCheckInRule)

    func testPostLowMoodRuleDoesNotRefireOnAlreadyNudgedCheckIn() async throws {
        // `PostLowMoodCheckInRule` reads its opt-in flag from
        // `UserDefaults.standard` directly (not the injectable `defaults`
        // seam), so this one key is set/cleared against `.standard`
        // deliberately — see tearDown.
        UserDefaults.standard.set(true, forKey: AppConstants.nudgePostLowMoodEnabledKey)
        let checkIn = CheckInRecord(
            id: "checkin-1",
            timeSlot: .morning,
            date: Self.fixedNow.addingTimeInterval(-60 * 30),
            completed: true,
            mood: 1,
            energyLevel: 2
        )
        context.insert(checkIn)
        // A prior nudge already references this check-in via triggerContext.
        insertDeliveredNudge(
            category: .postCheckInAction,
            createdAt: Self.fixedNow.addingTimeInterval(-60 * 25),
            triggerContextJSON: "{\"checkInID\":\"checkin-1\"}"
        )
        try context.save()

        let engine = makeEngine(rules: [PostLowMoodCheckInRule()])
        // patternEngine nil → streak 0 by default; the rule requires
        // `streak >= nudgePostLowMoodStreakMin`, so seed real completed
        // tasks on the last few real-world days (see makePatternEngine).
        engine.patternEngine = makePatternEngine(streakDays: AppConstants.nudgePostLowMoodStreakMin)
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 1, "already-nudged check-in must not produce a second nudge")
    }

    func testPostLowMoodRuleFiresForFreshQualifyingCheckIn() async throws {
        UserDefaults.standard.set(true, forKey: AppConstants.nudgePostLowMoodEnabledKey)
        let checkIn = CheckInRecord(
            id: "checkin-fresh",
            timeSlot: .morning,
            date: Self.fixedNow.addingTimeInterval(-60 * 30),
            completed: true,
            mood: 1,
            energyLevel: 2
        )
        context.insert(checkIn)
        try context.save()

        let engine = makeEngine(rules: [PostLowMoodCheckInRule()])
        engine.patternEngine = makePatternEngine(streakDays: AppConstants.nudgePostLowMoodStreakMin)
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 1, "a fresh qualifying low-mood check-in must produce exactly one nudge")
    }

    // MARK: - Dedupe: habits (WindowedHabitRule)

    func testWindowedHabitRuleDoesNotRefireSameHabitSameDay() async throws {
        let habit = makeWindowedHabit(id: "habit-1", window: .afternoon)
        context.insert(habit)
        insertDeliveredNudge(
            category: .windowedHabit,
            createdAt: dateAt(hour: 13),
            triggerContextJSON: "{\"habitID\":\"habit-1\"}"
        )
        try context.save()

        let engine = makeEngine(now: { self.dateAt(hour: 18) }, rules: [WindowedHabitRule()])
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 1, "a habit already nudged today must not be nudged again today")
    }

    func testWindowedHabitRuleFiresForFreshOpenHabit() async throws {
        let habit = makeWindowedHabit(id: "habit-2", window: .afternoon)
        context.insert(habit)
        try context.save()

        let engine = makeEngine(now: { self.dateAt(hour: 18) }, rules: [WindowedHabitRule()])
        await engine.evaluateOnForeground()
        let nudges = try allNudges()
        XCTAssertEqual(nudges.count, 1)
        XCTAssertEqual(nudges.first?.category, .windowedHabit)
    }

    private func makeWindowedHabit(id: String, window: HabitTimeWindow) -> HabitItem {
        let habit = HabitItem(
            id: id,
            title: "Stretch",
            dimension: .physical
        )
        habit.timeWindow = window
        return habit
    }

    /// `PatternEngine.currentStreak()` is final and reads real wall-clock
    /// `Date()` internally (not the engine's injectable `now`), so instead
    /// of subclassing (impossible — the class is `final`) we satisfy the
    /// streak gate with real completed `TaskItem`s on the actual last N
    /// real-world days, independent of the test's fixed `now` clock.
    private func makePatternEngine(streakDays: Int) -> PatternEngine {
        let cal = Calendar.current
        for offset in 0..<streakDays {
            let day = cal.date(byAdding: .day, value: -offset, to: Date())!
            let task = TaskItem(
                title: "seed-\(offset)",
                category: .personal,
                priority: .medium,
                date: day,
                done: true,
                icon: "circle"
            )
            context.insert(task)
        }
        try? context.save()
        return PatternEngine(modelContext: context)
    }

    // MARK: - Safety fingerprint stability

    func testSafetyNoteFingerprintIsStableForSameInput() {
        // If the implementation swapped `hashValue` for something seeded
        // per-process (or appended Date()), this would fail — two calls
        // with identical inputs in the same test run must match.
        let a = NudgeEngine.safetyNoteFingerprint(recordID: "rec-1", text: "I feel awful")
        let b = NudgeEngine.safetyNoteFingerprint(recordID: "rec-1", text: "I feel awful")
        XCTAssertEqual(a, b)
    }

    func testSafetyNoteFingerprintDiffersOnTextEdit() {
        // An edited note is treated as a fresh scan on purpose (not a bug) —
        // the fingerprint must change when the text changes.
        let a = NudgeEngine.safetyNoteFingerprint(recordID: "rec-1", text: "I feel awful")
        let b = NudgeEngine.safetyNoteFingerprint(recordID: "rec-1", text: "I feel fine now")
        XCTAssertNotEqual(a, b)
    }

    func testSafetyNoteFingerprintIsCaseAndWhitespaceInsensitive() {
        let a = NudgeEngine.safetyNoteFingerprint(recordID: "rec-1", text: "  Help Me  ")
        let b = NudgeEngine.safetyNoteFingerprint(recordID: "rec-1", text: "help me")
        XCTAssertEqual(a, b)
    }

    // MARK: - Safety precheck + pause

    func testCrisisFlagEmitsSafetyNudgeAndStartsPause() async throws {
        let checkIn = CheckInRecord(
            id: "crisis-checkin",
            timeSlot: .night,
            date: Self.fixedNow,
            completed: true,
            notes: "it's really bad tonight"
        )
        context.insert(checkIn)
        try context.save()

        let engine = makeEngine(
            now: { Self.fixedNow },
            rules: [],
            crisisClassifier: StubCrisisClassifier(result: CrisisEvaluation(isCrisis: true, matchedTerms: ["bad"]))
        )
        await engine.evaluateOnForeground()

        let nudges = try allNudges()
        XCTAssertEqual(nudges.count, 1)
        XCTAssertEqual(nudges.first?.category, .safetyRoute)
    }

    func testSafetyPauseBlocksAllEvaluationForTwentyFourHours() async throws {
        // After a crisis flag, step 2 (`isWithinSafetyPause`) must block
        // the ENTIRE evaluation — including unrelated, otherwise-eligible
        // rules — for 24h. If the pause check were skipped or scoped only
        // to the safety path, AlwaysFireRule below would fire.
        let checkIn = CheckInRecord(
            id: "crisis-checkin-2",
            timeSlot: .night,
            date: Self.fixedNow,
            completed: true,
            notes: "it's really bad tonight"
        )
        context.insert(checkIn)
        try context.save()

        var now = Self.fixedNow
        let engine = makeEngine(
            now: { now },
            rules: [AlwaysFireRule(id: .weakDimension)],
            crisisClassifier: StubCrisisClassifier(result: CrisisEvaluation(isCrisis: true, matchedTerms: ["bad"]))
        )
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 1, "only the safety nudge should exist after the first pass")

        // 1 hour later, well within the 24h pause — AlwaysFireRule must
        // still be blocked by the pause, not just skip because of its own
        // (irrelevant) cooldown.
        now = Self.fixedNow.addingTimeInterval(3600)
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 1, "safety pause must block unrelated rules for the full window")
    }

    func testSafetyPauseLiftsAfterTwentyFourHoursAllowingNormalRuleToFire() async throws {
        let checkIn = CheckInRecord(
            id: "crisis-checkin-3",
            timeSlot: .night,
            date: Self.fixedNow,
            completed: true,
            notes: "it's really bad tonight"
        )
        context.insert(checkIn)
        try context.save()

        var now = Self.fixedNow
        let engine = makeEngine(
            now: { now },
            rules: [AlwaysFireRule(id: .weakDimension)],
            crisisClassifier: StubCrisisClassifier(result: .safe)
        )
        // First pass: classifier is safe right now, so manufacture the
        // pause state directly to isolate "does it lift" from "does it
        // start", which is already covered above.
        defaults.set(now.addingTimeInterval(24 * 3600).timeIntervalSince1970, forKey: "coach.nudge.safetyPauseUntil")

        now = Self.fixedNow.addingTimeInterval(3600) // still inside pause
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 0, "still inside the pause window")

        now = Self.fixedNow.addingTimeInterval(24 * 3600 + 60) // just past it
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 1, "pause must lift once its window elapses")
    }

    func testSafetyFingerprintPreventsSecondEmitEvenAfterPauseIsCleared() async throws {
        // One-emit-per-fingerprint dedupe (Q1-BUG-26): without
        // `hasEmittedSafetyForFingerprint` gating the precheck, clearing
        // the pause (simulating "24h later, same unresolved note still on
        // record") would re-emit a second safety nudge and restart the
        // pause — an infinite loop risk for any user whose latest check-in
        // has ever matched.
        let checkIn = CheckInRecord(
            id: "crisis-checkin-4",
            timeSlot: .night,
            date: Self.fixedNow,
            completed: true,
            notes: "it's really bad tonight"
        )
        context.insert(checkIn)
        try context.save()

        let engine = makeEngine(
            now: { Self.fixedNow },
            rules: [],
            crisisClassifier: StubCrisisClassifier(result: CrisisEvaluation(isCrisis: true, matchedTerms: ["bad"]))
        )
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 1)

        // Manually clear the pause (as if 24h had passed) while leaving the
        // fingerprint record intact, then re-run against the SAME note.
        defaults.removeObject(forKey: "coach.nudge.safetyPauseUntil")
        await engine.evaluateOnForeground()
        XCTAssertEqual(try allNudges().count, 1, "the same flagged note must not re-emit once its fingerprint has been recorded")
    }

    // MARK: - recordResponse

    func testRecordResponseUpdatesStatusAndTimestamp() async throws {
        let engine = makeEngine(now: { Self.fixedNow })
        let nudge = Nudge(category: .weakDimension, bodyText: "test", status: .delivered)
        context.insert(nudge)
        try context.save()

        engine.recordResponse(nudgeID: nudge.id, response: .accepted)

        XCTAssertEqual(nudge.status, .responded)
        XCTAssertEqual(nudge.userResponse, .accepted)
        XCTAssertEqual(nudge.respondedAt, Self.fixedNow)
    }

    func testRecordResponseForUnknownIDIsANoOp() {
        let engine = makeEngine(now: { Self.fixedNow })
        // Must not throw / crash when no matching Nudge exists.
        engine.recordResponse(nudgeID: "does-not-exist", response: .dismissed)
    }

    // MARK: - Re-entrancy guard

    func testConcurrentEvaluationsOnlyProduceOneNudge() async throws {
        // Fix for Q1-BUG-27: `evaluate()` awaits the composer (an actor),
        // which suspends the MainActor — a second call arriving during
        // that suspension must be dropped by the `isEvaluating` guard,
        // not race its way into a second persisted nudge. If the guard
        // (or its `defer { isEvaluating = false }` reset) were removed,
        // both concurrent calls could independently pass the frequency/
        // cooldown checks (both reads happen before either write) and
        // persist two nudges.
        let engine = makeEngine(
            now: { Self.fixedNow },
            rules: [AlwaysFireRule(id: .weakDimension)]
        )
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await engine.evaluateOnForeground() }
            group.addTask { await engine.evaluateOnForeground() }
            await group.waitForAll()
        }
        XCTAssertEqual(try allNudges().count, 1, "only one of two concurrent evaluations must persist a nudge")
    }
}
