import XCTest
@testable import MyAIssistant

final class HomeProgressCalcTests: XCTestCase {
    // MARK: - dayCompletionFraction

    func test_dayCompletionFraction_noTasksNoCheckIns_isZero() {
        let fraction = HomeProgressCalc.dayCompletionFraction(
            completedTasks: 0, totalTasks: 0, completedCheckIns: 0
        )
        XCTAssertEqual(fraction, 0)
    }

    func test_dayCompletionFraction_noTasksAllCheckInsDone_isFullyComplete() {
        // The audit's core fix: 0 tasks + 4/4 check-ins should read 100%,
        // not divide by a phantom task denominator.
        let fraction = HomeProgressCalc.dayCompletionFraction(
            completedTasks: 0, totalTasks: 0, completedCheckIns: 4
        )
        XCTAssertEqual(fraction, 1.0, accuracy: 0.0001)
    }

    func test_dayCompletionFraction_blendsTasksAndCheckIns() {
        // 2 of 2 tasks + 2 of 4 check-ins = 4 of 6 units.
        let fraction = HomeProgressCalc.dayCompletionFraction(
            completedTasks: 2, totalTasks: 2, completedCheckIns: 2
        )
        XCTAssertEqual(fraction, 4.0 / 6.0, accuracy: 0.0001)
    }

    func test_dayCompletionFraction_clampsAboveOne() {
        let fraction = HomeProgressCalc.dayCompletionFraction(
            completedTasks: 10, totalTasks: 2, completedCheckIns: 10
        )
        XCTAssertEqual(fraction, 1.0, accuracy: 0.0001)
    }

    // MARK: - shouldShowRemainingItemsInsteadOfPercent

    func test_shouldShowRemainingItems_zeroFractionEvening_true() {
        XCTAssertTrue(
            HomeProgressCalc.shouldShowRemainingItemsInsteadOfPercent(
                dayCompletionFraction: 0, hour: 18
            )
        )
    }

    func test_shouldShowRemainingItems_zeroFractionMorning_false() {
        XCTAssertFalse(
            HomeProgressCalc.shouldShowRemainingItemsInsteadOfPercent(
                dayCompletionFraction: 0, hour: 9
            )
        )
    }

    func test_shouldShowRemainingItems_nonZeroFractionEvening_false() {
        XCTAssertFalse(
            HomeProgressCalc.shouldShowRemainingItemsInsteadOfPercent(
                dayCompletionFraction: 0.5, hour: 20
            )
        )
    }

    func test_shouldShowRemainingItems_boundaryHourSix_true() {
        XCTAssertTrue(
            HomeProgressCalc.shouldShowRemainingItemsInsteadOfPercent(
                dayCompletionFraction: 0, hour: 18
            )
        )
    }

    func test_shouldShowRemainingItems_hourBeforeSix_false() {
        XCTAssertFalse(
            HomeProgressCalc.shouldShowRemainingItemsInsteadOfPercent(
                dayCompletionFraction: 0, hour: 17
            )
        )
    }

    // MARK: - remainingItemsText

    func test_remainingItemsText_allClear() {
        let text = HomeProgressCalc.remainingItemsText(
            completedTasks: 3, totalTasks: 3, completedCheckIns: 4
        )
        XCTAssertEqual(text, "all clear")
    }

    func test_remainingItemsText_tasksAndCheckInsLeft() {
        let text = HomeProgressCalc.remainingItemsText(
            completedTasks: 1, totalTasks: 3, completedCheckIns: 1
        )
        XCTAssertEqual(text, "2 tasks, 3 check-ins left")
    }

    func test_remainingItemsText_singularPluralization() {
        let text = HomeProgressCalc.remainingItemsText(
            completedTasks: 0, totalTasks: 1, completedCheckIns: 3
        )
        XCTAssertEqual(text, "1 task, 1 check-in left")
    }

    func test_remainingItemsText_onlyCheckInsLeft() {
        let text = HomeProgressCalc.remainingItemsText(
            completedTasks: 0, totalTasks: 0, completedCheckIns: 0
        )
        XCTAssertEqual(text, "4 check-ins left")
    }

    // MARK: - shouldShowTonightCard (Evening Flow redesign)

    func test_shouldShowTonightCard_eveningAndNotDone_true() {
        XCTAssertTrue(
            HomeProgressCalc.shouldShowTonightCard(hour: 19, nightCheckInDone: false)
        )
    }

    func test_shouldShowTonightCard_boundaryHourSix_true() {
        XCTAssertTrue(
            HomeProgressCalc.shouldShowTonightCard(hour: 18, nightCheckInDone: false)
        )
    }

    func test_shouldShowTonightCard_beforeEvening_false() {
        XCTAssertFalse(
            HomeProgressCalc.shouldShowTonightCard(hour: 17, nightCheckInDone: false)
        )
    }

    func test_shouldShowTonightCard_eveningButAlreadyDone_false() {
        XCTAssertFalse(
            HomeProgressCalc.shouldShowTonightCard(hour: 22, nightCheckInDone: true)
        )
    }

    func test_shouldShowTonightCard_morningAndDone_false() {
        XCTAssertFalse(
            HomeProgressCalc.shouldShowTonightCard(hour: 8, nightCheckInDone: true)
        )
    }
}
