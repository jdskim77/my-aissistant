import XCTest
import SwiftData
@testable import MyAIssistant

/// Characterization tests for `BalanceManager`.
///
/// `BalanceManager` is a 1,180-line god class slated for a split into
/// scoring / check-in store / season-goal store / activity-recall engines.
/// These tests pin its CURRENT observable behavior so the extraction can be
/// verified behavior-preserving: store/state ROUND-TRIPS (check-in,
/// satisfaction, season goal, personal target) and core scoring INVARIANTS
/// (empty-state, range, structure). They deliberately avoid asserting exact
/// composite scores — those are the formulas being refactored; round-trips
/// and invariants are the contract that must survive.
@MainActor
final class BalanceManagerTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var sut: BalanceManager!

    override func setUp() async throws {
        container = try TestModelContainer.create()
        context = container.mainContext
        sut = BalanceManager(modelContext: context)
        clearPersonalTargets()
    }

    override func tearDown() async throws {
        // personalTarget uses UserDefaults.standard (global) — keep tests
        // order-independent by clearing the keys on both ends.
        clearPersonalTargets()
        container = nil
        context = nil
        sut = nil
    }

    private func clearPersonalTargets() {
        for dim in LifeDimension.scored {
            UserDefaults.standard.removeObject(forKey: "balanceTarget_\(dim.rawValue)")
        }
    }

    private func addDoneTaskThisWeek(_ dimension: LifeDimension = .physical) {
        let task = TaskItem(
            title: "Done task",
            category: .personal,
            priority: .medium,
            date: Date(),
            done: true,
            icon: "✅"
        )
        task.dimension = dimension
        context.insert(task)
        try? context.save()
    }

    // MARK: - Empty state

    func test_emptyState_hasNoRealData() {
        XCTAssertFalse(sut.hasRealData())
    }

    func test_emptyState_notCheckedInToday() {
        XCTAssertFalse(sut.hasCheckedInToday())
        XCTAssertTrue(sut.todaySatisfaction().isEmpty)
        XCTAssertNil(sut.weeklyEnergyAverage())
    }

    func test_emptyState_balanceStreakIsZero() {
        XCTAssertEqual(sut.balanceStreak(), 0)
    }

    func test_emptyState_noActiveSeasonGoal() {
        XCTAssertNil(sut.activeSeasonGoal())
        XCTAssertNil(sut.seasonGoalProgress())
    }

    // MARK: - Scoring invariants

    func test_weeklyBreakdowns_coversEveryScoredDimension() {
        let breakdowns = sut.weeklyBreakdowns()
        for dim in LifeDimension.scored {
            XCTAssertNotNil(breakdowns[dim], "missing breakdown for \(dim.rawValue)")
        }
    }

    func test_balanceScore_isWithinZeroToTen() {
        let score = sut.balanceScore()
        XCTAssertGreaterThanOrEqual(score, 0)
        XCTAssertLessThanOrEqual(score, 10)
    }

    func test_weeklyScores_allWithinZeroToTen() {
        for (dim, score) in sut.weeklyScores() {
            XCTAssertGreaterThanOrEqual(score, 0, "\(dim.rawValue) below 0")
            XCTAssertLessThanOrEqual(score, 10, "\(dim.rawValue) above 10")
        }
    }

    func test_dimensionBreakdownComposite_isWeightedSumOfSignals() {
        let bd = BalanceManager.DimensionBreakdown(activity: 10, satisfaction: 5, consistency: 0)
        // 10*0.30 + 5*0.40 + 0*0.30 = 5.0
        XCTAssertEqual(bd.composite, 5.0, accuracy: 0.0001)
    }

    // MARK: - Check-in / satisfaction round-trips

    func test_recordSatisfaction_roundTripsThroughTodaySatisfaction() {
        sut.recordSatisfaction(ratings: [.physical: 4, .mental: 2])

        XCTAssertTrue(sut.hasCheckedInToday())
        let today = sut.todaySatisfaction()
        XCTAssertEqual(today[.physical], 4)
        XCTAssertEqual(today[.mental], 2)
    }

    func test_recordSatisfaction_clampsRatingsToOneThroughFive() {
        sut.recordSatisfaction(ratings: [.physical: 9, .mental: -3])
        let today = sut.todaySatisfaction()
        XCTAssertEqual(today[.physical], 5)
        XCTAssertEqual(today[.mental], 1)
    }

    func test_recordSatisfaction_energyFeedsWeeklyAverage() {
        sut.recordSatisfaction(ratings: [.physical: 3], energyRating: 2)
        XCTAssertEqual(sut.weeklyEnergyAverage() ?? .nan, 2.0, accuracy: 0.0001)
    }

    func test_recordCheckIn_marksCheckedInToday() {
        sut.recordCheckIn(dimension: .emotional, energyRating: 1)
        XCTAssertTrue(sut.hasCheckedInToday())
    }

    func test_hasRealData_trueAfterDoneTaskThisWeek() {
        XCTAssertFalse(sut.hasRealData())
        addDoneTaskThisWeek()
        XCTAssertTrue(sut.hasRealData())
    }

    // MARK: - Season goal round-trips

    func test_startSeasonGoal_becomesActiveWithDimensionAndIntention() {
        sut.startSeasonGoal(dimension: .spiritual, intention: "Meditate daily")

        let goal = sut.activeSeasonGoal()
        XCTAssertNotNil(goal)
        XCTAssertEqual(goal?.dimension, .spiritual)
        XCTAssertEqual(goal?.intention, "Meditate daily")
    }

    func test_completeSeasonGoal_clearsActiveGoal() {
        sut.startSeasonGoal(dimension: .physical, intention: "Run 3x/week")
        XCTAssertNotNil(sut.activeSeasonGoal())

        sut.completeSeasonGoal()
        XCTAssertNil(sut.activeSeasonGoal())
    }

    func test_startSeasonGoal_replacesPreviousActiveGoal() {
        sut.startSeasonGoal(dimension: .physical, intention: "First")
        sut.startSeasonGoal(dimension: .mental, intention: "Second")

        // Only the most recent goal is active; the first was auto-completed.
        XCTAssertEqual(sut.activeSeasonGoal()?.dimension, .mental)
    }

    // MARK: - Personal target round-trip

    func test_setPersonalTarget_roundTripsPerDimension() {
        sut.setPersonalTarget(7, for: .physical)
        XCTAssertEqual(sut.personalTarget(for: .physical), 7)
    }

    func test_setPersonalTarget_clampsToAtLeastOne() {
        sut.setPersonalTarget(0, for: .mental)
        XCTAssertGreaterThanOrEqual(sut.personalTarget(for: .mental), 1)
    }

    func test_personalTarget_withoutDimension_returnsPositiveDefault() {
        XCTAssertGreaterThan(sut.personalTarget(), 0)
    }
}
