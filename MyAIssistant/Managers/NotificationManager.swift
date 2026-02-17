import Foundation
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    @Published var isAuthorized = false

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            if granted {
                registerCategories()
            }
            return granted
        } catch {
            return false
        }
    }

    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Check-in Reminders

    func scheduleCheckInReminders() {
        let center = UNUserNotificationCenter.current()

        // Remove existing check-in notifications
        center.removePendingNotificationRequests(withIdentifiers:
            CheckInTime.allCases.map { "checkin-\($0.rawValue)" }
        )

        for checkIn in CheckInTime.allCases {
            let content = UNMutableNotificationContent()
            content.title = checkIn.title
            content.body = checkIn.greeting
            content.sound = .default
            content.categoryIdentifier = "CHECKIN"
            content.userInfo = ["timeSlot": checkIn.rawValue]

            var dateComponents = DateComponents()
            dateComponents.hour = checkIn.hour
            dateComponents.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: "checkin-\(checkIn.rawValue)",
                content: content,
                trigger: trigger
            )

            center.add(request)
        }
    }

    // MARK: - Task Reminders

    func scheduleTaskReminder(taskID: String, title: String, date: Date) {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "Task Due Soon"
        content.body = title
        content.sound = .default
        content.categoryIdentifier = "TASK"
        content.userInfo = ["taskID": taskID]

        // Remind 30 minutes before
        let reminderDate = date.addingTimeInterval(-Double(AppConstants.taskReminderLeadMinutes * 60))
        guard reminderDate > Date() else { return }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "task-\(taskID)",
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    func cancelTaskReminder(taskID: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["task-\(taskID)"])
    }

    // MARK: - Cancel All

    func cancelAllReminders() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Notification Categories

    private func registerCategories() {
        let completeAction = UNNotificationAction(
            identifier: "COMPLETE_CHECKIN",
            title: "Start Check-in",
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: []
        )

        let checkInCategory = UNNotificationCategory(
            identifier: "CHECKIN",
            actions: [completeAction, dismissAction],
            intentIdentifiers: []
        )

        let markDoneAction = UNNotificationAction(
            identifier: "MARK_DONE",
            title: "Mark Done",
            options: []
        )
        let taskCategory = UNNotificationCategory(
            identifier: "TASK",
            actions: [markDoneAction, dismissAction],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current()
            .setNotificationCategories([checkInCategory, taskCategory])
    }
}
