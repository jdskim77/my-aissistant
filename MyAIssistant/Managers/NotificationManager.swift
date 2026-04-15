import Foundation
import Observation
import UserNotifications

// MARK: - Engine / Reusable (with Thrivn-specific scheduling logic flagged)
//
// Local notification scheduling, permission handling, and adaptive frequency
// based on user engagement (streaks). The TIMING ENGINE is generic; the
// SLOTS being scheduled (Morning/Midday/Afternoon/Night check-ins) are
// Thrivn-specific.
//
// REUSABLE (keep in fork):
//   - Permission request flow
//   - Notification category + action registration
//   - Daily-recurring-time scheduling primitive
//   - Frequency tier mechanism (full/moderate/minimal based on streak)
//   - Badge management
//
// ⚠️ THRIVN-SPECIFIC — REPLACE IN FORK:
//   - The 4-slot CheckInTime model (morning/midday/afternoon/night) and
//     the per-slot scheduling methods. A surf or other app will have its
//     own cadence (sunrise/sunset for surf? meal times for nutrition?).
//   - The motivational copy in notification bodies.
//   - The streak thresholds for frequency tiers.
//
// Dependencies: UserNotifications, Foundation. Optional: BehaviorEngine
// (smart timing).

// MARK: - Notification Frequency

enum NotificationFrequency: String {
    case full       // All 4 check-in reminders (streak 0-7)
    case moderate   // 2 reminders: morning + evening (streak 8-21)
    case minimal    // Streak-at-risk only (streak 22+)

    static func forStreak(_ streak: Int) -> NotificationFrequency {
        if streak >= AppConstants.minimalStreakThreshold {
            return .minimal
        } else if streak >= AppConstants.moderateStreakThreshold {
            return .moderate
        } else {
            return .full
        }
    }
}

@Observable @MainActor
final class NotificationManager {
    var isAuthorized = false

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
        if isAuthorized {
            registerCategories()
        }
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

    // MARK: - Alarms

    func scheduleAlarm(notificationID: String, label: String, time: Date, repeatsDaily: Bool) {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "Alarm"
        content.body = label
        content.sound = UNNotificationSound.defaultCritical
        content.categoryIdentifier = "ALARM"
        content.userInfo = ["alarmID": notificationID]
        content.interruptionLevel = .timeSensitive

        let components: DateComponents
        if repeatsDaily {
            components = Calendar.current.dateComponents([.hour, .minute], from: time)
        } else {
            components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: time
            )
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeatsDaily)
        let request = UNNotificationRequest(
            identifier: "alarm-\(notificationID)",
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    func cancelAlarm(notificationID: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["alarm-\(notificationID)"])
    }

    // MARK: - Adaptive Check-in Scheduling

    /// Schedules check-in reminders based on the user's current streak.
    /// Higher streaks mean fewer reminders (the habit is forming).
    func scheduleAdaptiveCheckInReminders(currentStreak: Int) {
        let frequency = NotificationFrequency.forStreak(currentStreak)

        // Persist the frequency tier
        UserDefaults.standard.set(frequency.rawValue, forKey: AppConstants.notificationFrequencyKey)

        let center = UNUserNotificationCenter.current()

        // Remove all existing check-in notifications
        center.removePendingNotificationRequests(withIdentifiers:
            CheckInTime.allCases.map { "checkin-\($0.rawValue)" }
        )

        let slotsToSchedule: [CheckInTime]
        switch frequency {
        case .full:
            slotsToSchedule = Array(CheckInTime.allCases)
        case .moderate:
            slotsToSchedule = [.morning, .afternoon]  // Morning + evening (6 PM)
        case .minimal:
            // No regular check-in reminders — rely on streak-at-risk only
            slotsToSchedule = []
        }

        for checkIn in slotsToSchedule {
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

        // Always schedule streak-at-risk for streaks > 0
        scheduleStreakAtRiskReminder(currentStreak: currentStreak)
    }

    // MARK: - Streak-at-Risk Notifications

    /// Schedules an evening reminder (8 PM) if the user has an active streak.
    /// Message varies by streak length to increase urgency proportionally.
    func scheduleStreakAtRiskReminder(currentStreak: Int) {
        let center = UNUserNotificationCenter.current()
        let identifier = AppConstants.streakReminderIdentifier

        // Remove any existing streak reminder
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard currentStreak > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Streak Reminder"
        content.sound = .default
        content.categoryIdentifier = "STREAK_REMINDER"

        switch currentStreak {
        case 1...6:
            content.body = "Don't forget to check in today!"
        case 7...20:
            content.body = "Your \(currentStreak)-day streak is on the line! Check in before midnight."
        default:
            content.body = "You've built something incredible — \(currentStreak) days strong. Don't let it slip tonight."
        }

        var dateComponents = DateComponents()
        dateComponents.hour = AppConstants.streakReminderHour
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    /// Cancels the streak-at-risk reminder (call after user checks in).
    func cancelStreakReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [AppConstants.streakReminderIdentifier])
    }

    // MARK: - Habit Reminders

    /// Schedule daily reminders for all active habits that have a reminder time set.
    func scheduleHabitReminders(_ habits: [HabitItem]) {
        let center = UNUserNotificationCenter.current()

        // Remove ALL existing habit reminders (including archived/deleted ones)
        center.getPendingNotificationRequests { requests in
            let habitIDs = requests
                .filter { $0.identifier.hasPrefix("habit-") }
                .map(\.identifier)
            if !habitIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: habitIDs)
            }
        }

        for habit in habits where !habit.isArchived {
            guard let hour = habit.reminderHour, let minute = habit.reminderMinute else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(habit.icon) \(habit.title)"
            content.body = habitReminderBody(for: habit)
            content.sound = .default
            content.categoryIdentifier = "HABIT"
            content.userInfo = ["habitID": habit.id]

            var dateComponents = DateComponents()
            dateComponents.hour = hour
            dateComponents.minute = minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: "habit-\(habit.id)",
                content: content,
                trigger: trigger
            )

            center.add(request)
        }
    }

    /// Cancel reminder for a specific habit (e.g., when archived or deleted).
    func cancelHabitReminder(habitID: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["habit-\(habitID)"])
    }

    private func habitReminderBody(for habit: HabitItem) -> String {
        let streak = habit.currentStreak()
        if streak >= 7 {
            return "\(streak)-day streak going. Keep it alive."
        } else if streak >= 3 {
            return "\(streak) days in a row — building momentum."
        } else {
            return "Time for your daily \(habit.title.lowercased())."
        }
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

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ALARM",
            title: "Snooze (5 min)",
            options: []
        )
        let stopAlarmAction = UNNotificationAction(
            identifier: "STOP_ALARM",
            title: "Stop",
            options: [.destructive]
        )
        let alarmCategory = UNNotificationCategory(
            identifier: "ALARM",
            actions: [snoozeAction, stopAlarmAction],
            intentIdentifiers: []
        )

        let streakCheckInAction = UNNotificationAction(
            identifier: "COMPLETE_CHECKIN",
            title: "Check In Now",
            options: [.foreground]
        )
        let streakCategory = UNNotificationCategory(
            identifier: "STREAK_REMINDER",
            actions: [streakCheckInAction, dismissAction],
            intentIdentifiers: []
        )

        let completeHabitAction = UNNotificationAction(
            identifier: "COMPLETE_HABIT",
            title: "Done",
            options: []
        )
        let habitCategory = UNNotificationCategory(
            identifier: "HABIT",
            actions: [completeHabitAction, dismissAction],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current()
            .setNotificationCategories([checkInCategory, taskCategory, alarmCategory, streakCategory, habitCategory])
    }
}
