import XCTest
@testable import MyAIssistant

/// Pure-logic tests for the Feature 1 quick-check-in decision helpers.
/// `QuickCheckInLogic` is framework-free, so none of these need a
/// ModelContainer or UNUserNotificationCenter.
final class QuickCheckInLogicTests: XCTestCase {

    // MARK: - Mood Actions

    func testMoodActionIdentifiersAreDistinctAndNonForegroundByConvention() {
        let specs = QuickCheckInLogic.moodActionSpecs
        XCTAssertEqual(specs.count, 5, "Expect one action per point on the 5-point mood scale")
        XCTAssertEqual(Set(specs.map(\.identifier)).count, 5, "Identifiers must be unique")
        XCTAssertEqual(Set(specs.map(\.value)), Set(1...5))
    }

    func testMoodValueForActionIdentifierRoundTrips() {
        for spec in QuickCheckInLogic.moodActionSpecs {
            XCTAssertEqual(QuickCheckInLogic.moodValue(forActionIdentifier: spec.identifier), spec.value)
        }
    }

    func testMoodValueForNonMoodIdentifierIsNil() {
        XCTAssertNil(QuickCheckInLogic.moodValue(forActionIdentifier: "COMPLETE_CHECKIN"))
        XCTAssertNil(QuickCheckInLogic.moodValue(forActionIdentifier: "DISMISS"))
        XCTAssertNil(QuickCheckInLogic.moodValue(forActionIdentifier: "garbage"))
    }

    // MARK: - Slot Derivation

    func testExplicitSlotWins() {
        XCTAssertEqual(
            QuickCheckInLogic.deriveTimeSlot(explicitRaw: "Morning", hour: 20),
            .morning
        )
    }

    func testInvalidExplicitSlotFallsBackToHour() {
        XCTAssertEqual(
            QuickCheckInLogic.deriveTimeSlot(explicitRaw: "NotARealSlot", hour: 9),
            .morning
        )
    }

    func testSlotForHourBoundaries() {
        XCTAssertEqual(QuickCheckInLogic.slot(forHour: 0), .night)
        XCTAssertEqual(QuickCheckInLogic.slot(forHour: 2), .night)
        XCTAssertEqual(QuickCheckInLogic.slot(forHour: 3), .morning)
        XCTAssertEqual(QuickCheckInLogic.slot(forHour: 10), .morning)
        XCTAssertEqual(QuickCheckInLogic.slot(forHour: 11), .midday)
        XCTAssertEqual(QuickCheckInLogic.slot(forHour: 15), .midday)
        XCTAssertEqual(QuickCheckInLogic.slot(forHour: 16), .afternoon)
        XCTAssertEqual(QuickCheckInLogic.slot(forHour: 19), .afternoon)
        XCTAssertEqual(QuickCheckInLogic.slot(forHour: 20), .night)
        XCTAssertEqual(QuickCheckInLogic.slot(forHour: 23), .night)
    }

    func testNoExplicitSlotDerivesFromHour() {
        XCTAssertEqual(QuickCheckInLogic.deriveTimeSlot(explicitRaw: nil, hour: 14), .midday)
    }

    // MARK: - Find-or-Create (no double recording)

    func testDecideCreateAndCompleteWhenNoRecordExists() {
        let decision = QuickCheckInLogic.decide(for: .morning, existingToday: [])
        XCTAssertEqual(decision, .createAndComplete)
    }

    func testDecideCompleteExistingPendingRecord() {
        let existing = [QuickCheckInLogic.ExistingRecordSummary(timeSlotRaw: "Morning", completed: false)]
        XCTAssertEqual(QuickCheckInLogic.decide(for: .morning, existingToday: existing), .completeExistingPending)
    }

    func testDecideAlreadyCompletedDoesNotDoubleRecord() {
        let existing = [QuickCheckInLogic.ExistingRecordSummary(timeSlotRaw: "Morning", completed: true)]
        XCTAssertEqual(QuickCheckInLogic.decide(for: .morning, existingToday: existing), .alreadyCompleted)
    }

    func testDecideIgnoresOtherSlotsRecords() {
        let existing = [QuickCheckInLogic.ExistingRecordSummary(timeSlotRaw: "Night", completed: true)]
        XCTAssertEqual(QuickCheckInLogic.decide(for: .morning, existingToday: existing), .createAndComplete)
    }

    // MARK: - Reward Notification Copy

    func testRewardNotificationBodyWithInsight() {
        let body = QuickCheckInLogic.rewardNotificationBody(moodValue: 4, streak: 7, insightText: "Your mood dips on Mondays.")
        XCTAssertEqual(body, "Logged: Good. 🔥 7-day streak. Your mood dips on Mondays.")
    }

    func testRewardNotificationBodyWithoutInsight() {
        let body = QuickCheckInLogic.rewardNotificationBody(moodValue: 1, streak: 0, insightText: nil)
        XCTAssertEqual(body, "Logged: Rough. 🔥 0-day streak")
    }

    func testRewardNotificationBodyIgnoresEmptyInsight() {
        let body = QuickCheckInLogic.rewardNotificationBody(moodValue: 3, streak: 2, insightText: "")
        XCTAssertEqual(body, "Logged: Okay. 🔥 2-day streak")
    }

    func testRewardNotificationTitleIncludesMoodEmoji() {
        let title = QuickCheckInLogic.rewardNotificationTitle(moodValue: 5)
        XCTAssertTrue(title.contains("😄"))
        XCTAssertTrue(title.contains("Check-in logged"))
    }

    // MARK: - Fallback Insight Text (tone check)

    func testFallbackInsightTextIsFactualNotCheerleading() {
        let text = QuickCheckInLogic.fallbackInsightText()
        XCTAssertFalse(text.contains("!"), "NUDGE_ENGINE_SPEC non-goals: no cheerleading / exclamation tone")
        XCTAssertFalse(text.lowercased().contains("great job"))
        XCTAssertFalse(text.isEmpty)
    }

    // MARK: - Streak Reminder Next-Fire-Date (8pm bug fix)

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    func testNextFireDateIsTodayWhenNotYetCheckedInAndBefore8pm() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = date(2026, 3, 10, 14, 0)
        let fireDate = QuickCheckInLogic.nextStreakReminderFireDate(
            now: now, alreadyCheckedInToday: false, hour: 20, calendar: calendar
        )
        XCTAssertEqual(fireDate, date(2026, 3, 10, 20, 0))
    }

    func testNextFireDateSkipsTodayWhenAlreadyCheckedIn() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = date(2026, 3, 10, 9, 0) // well before 8pm
        let fireDate = QuickCheckInLogic.nextStreakReminderFireDate(
            now: now, alreadyCheckedInToday: true, hour: 20, calendar: calendar
        )
        XCTAssertEqual(fireDate, date(2026, 3, 11, 20, 0), "Should roll to tomorrow, not fire again today")
    }

    func testNextFireDateRollsToTomorrowWhen8pmAlreadyPassed() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = date(2026, 3, 10, 21, 30) // after 8pm, not checked in
        let fireDate = QuickCheckInLogic.nextStreakReminderFireDate(
            now: now, alreadyCheckedInToday: false, hour: 20, calendar: calendar
        )
        XCTAssertEqual(fireDate, date(2026, 3, 11, 20, 0))
    }
}
