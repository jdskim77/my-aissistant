import XCTest
@testable import MyAIssistant

final class DateHelpersTests: XCTestCase {

    // MARK: - Calendar.safeDate

    func testSafeDateByAddingDay() {
        let now = Date()
        let tomorrow = Calendar.current.safeDate(byAdding: .day, value: 1, to: now)
        let diff = Calendar.current.dateComponents([.day], from: now, to: tomorrow)
        XCTAssertEqual(diff.day, 1)
    }

    func testSafeDateByAddingNegative() {
        let now = Date()
        let yesterday = Calendar.current.safeDate(byAdding: .day, value: -1, to: now)
        let diff = Calendar.current.dateComponents([.day], from: yesterday, to: now)
        XCTAssertEqual(diff.day, 1)
    }

    func testSafeDateByAddingMonth() {
        let now = Date()
        let nextMonth = Calendar.current.safeDate(byAdding: .month, value: 1, to: now)
        let diff = Calendar.current.dateComponents([.month], from: now, to: nextMonth)
        XCTAssertEqual(diff.month, 1)
    }

    func testSafeDateByAddingZero() {
        let now = Date()
        let same = Calendar.current.safeDate(byAdding: .day, value: 0, to: now)
        XCTAssertEqual(same.timeIntervalSinceReferenceDate, now.timeIntervalSinceReferenceDate, accuracy: 1)
    }

    // MARK: - Date.startOfDay

    func testStartOfDay() {
        let now = Date()
        let start = now.startOfDay
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: start)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 0)
    }

    // MARK: - Date.endOfDay

    func testEndOfDay() {
        let now = Date()
        let end = now.endOfDay
        // endOfDay should be the start of the next day
        let start = now.startOfDay
        let diff = Calendar.current.dateComponents([.day], from: start, to: end)
        XCTAssertEqual(diff.day, 1)
    }

    // MARK: - Date.isToday

    func testIsTodayForNow() {
        XCTAssertTrue(Date().isToday)
    }

    func testIsTodayForYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertFalse(yesterday.isToday)
    }

    func testIsTodayForTomorrow() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertFalse(tomorrow.isToday)
    }

    // MARK: - Date.isTomorrow

    func testIsTomorrowForTomorrow() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertTrue(tomorrow.isTomorrow)
    }

    func testIsTomorrowForToday() {
        XCTAssertFalse(Date().isTomorrow)
    }

    // MARK: - Date.formatted(as:)

    func testFormattedAsYear() {
        let date = Date.from(month: 6, day: 15, year: 2026)
        let result = date.formatted(as: "yyyy")
        XCTAssertEqual(result, "2026")
    }

    func testFormattedAsMonthDay() {
        let date = Date.from(month: 3, day: 5, year: 2026)
        let result = date.formatted(as: "MM-dd")
        XCTAssertEqual(result, "03-05")
    }

    func testFormattedAsFullDate() {
        let date = Date.from(month: 12, day: 25, year: 2026, hour: 14)
        let result = date.formatted(as: "yyyy-MM-dd")
        XCTAssertEqual(result, "2026-12-25")
    }

    // MARK: - Date.from(month:day:year:hour:)

    func testDateFromComponents() {
        let date = Date.from(month: 2, day: 14, year: 2026, hour: 10)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 14)
        XCTAssertEqual(components.hour, 10)
    }

    func testDateFromComponentsDefaultHour() {
        let date = Date.from(month: 1, day: 1)
        let components = Calendar.current.dateComponents([.hour], from: date)
        XCTAssertEqual(components.hour, 9) // default hour is 9
    }

    func testDateFromComponentsDefaultYear() {
        let date = Date.from(month: 6, day: 15)
        let components = Calendar.current.dateComponents([.year], from: date)
        XCTAssertEqual(components.year, 2026) // default year is 2026
    }

    // MARK: - Edge Cases

    func testStartOfDayIdempotent() {
        let now = Date()
        let start = now.startOfDay
        let startAgain = start.startOfDay
        XCTAssertEqual(start, startAgain)
    }

    func testEndOfDayIsStartOfNextDay() {
        let now = Date()
        let end = now.endOfDay
        let nextDayStart = Calendar.current.date(byAdding: .day, value: 1, to: now.startOfDay)!
        XCTAssertEqual(end.timeIntervalSinceReferenceDate, nextDayStart.timeIntervalSinceReferenceDate, accuracy: 1)
    }
}
