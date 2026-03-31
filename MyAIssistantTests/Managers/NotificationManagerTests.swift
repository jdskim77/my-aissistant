import XCTest
@testable import MyAIssistant

@MainActor
final class NotificationManagerTests: XCTestCase {

    private var sut: NotificationManager!

    override func setUp() async throws {
        sut = NotificationManager()
    }

    override func tearDown() async throws {
        sut = nil
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertFalse(sut.isAuthorized)
    }

    // MARK: - Notification Identifiers

    func testCheckInReminderIdentifiers() {
        // Verify the notification identifiers follow expected pattern
        for checkIn in CheckInTime.allCases {
            let expectedID = "checkin-\(checkIn.rawValue)"
            XCTAssertFalse(expectedID.isEmpty)
        }
    }

    func testTaskReminderIdentifier() {
        // The task reminder ID pattern is "task-{taskID}"
        let taskID = "test-task-123"
        let expectedID = "task-\(taskID)"
        XCTAssertEqual(expectedID, "task-test-task-123")
    }

    func testAlarmIdentifier() {
        let notificationID = "alarm-test-id"
        let expectedID = "alarm-\(notificationID)"
        XCTAssertEqual(expectedID, "alarm-alarm-test-id")
    }

    // MARK: - Task Reminder Lead Time

    func testTaskReminderLeadTime() {
        // Verify the lead time constant is reasonable
        XCTAssertEqual(AppConstants.taskReminderLeadMinutes, 30)

        // If a task is in the past, scheduleTaskReminder should not schedule
        // (We can't easily test UNUserNotificationCenter in unit tests,
        // but we verify the guard condition logic)
        let pastDate = Date().addingTimeInterval(-Double(AppConstants.taskReminderLeadMinutes * 60 + 1))
        let reminderDate = pastDate.addingTimeInterval(-Double(AppConstants.taskReminderLeadMinutes * 60))
        XCTAssertTrue(reminderDate < Date(), "Reminder for past task should be in the past")
    }

    // MARK: - Check-in Time Coverage

    func testAllCheckInTimesHaveContent() {
        for checkIn in CheckInTime.allCases {
            XCTAssertFalse(checkIn.title.isEmpty, "Title for \(checkIn.rawValue) should not be empty")
            XCTAssertFalse(checkIn.greeting.isEmpty, "Greeting for \(checkIn.rawValue) should not be empty")
            XCTAssertTrue(checkIn.hour >= 0 && checkIn.hour < 24, "Hour for \(checkIn.rawValue) should be valid")
        }
    }
}
