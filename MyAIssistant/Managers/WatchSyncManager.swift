import Foundation
import Observation
import WatchConnectivity
import os.log

/// Manages iPhone → Watch data sync via WatchConnectivity.
/// Sends schedule snapshots to the Watch app whenever tasks change.
@Observable @MainActor
final class WatchSyncManager: NSObject {
    static let shared = WatchSyncManager()
    private var session: WCSession?
    private var isActivated = false
    /// Pending sync to fire once session activates
    private var pendingSync: (() -> Void)?

    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    /// Send API key to Watch so it can make direct Claude API calls.
    func syncAPIKey() {
        guard let session else { return }
        guard isActivated, session.isPaired, session.isWatchAppInstalled else { return }
        let keychain = KeychainService()
        guard let apiKey = keychain.anthropicAPIKey(), !apiKey.isEmpty else { return }
        let message = ["apiKey": apiKey]
        // Use both channels to ensure delivery
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil)
        }
        // Also include in application context for when Watch isn't reachable
        var context = session.applicationContext
        context["apiKey"] = apiKey
        context["textSize"] = TextSizeManager.shared.selectedSize.rawValue
        try? session.updateApplicationContext(context)
    }

    /// Send current schedule to Watch. Call after any task mutation.
    func syncSchedule(
        tasks: [TaskItem],
        streak: Int,
        quoteText: String?,
        quoteAuthor: String?,
        compassScores: (body: Double, mind: Double, heart: Double, spirit: Double)? = nil,
        userName: String? = nil,
        aiInsight: String? = nil,
        completedCheckIns: [String]? = nil
    ) {
        guard let session else { return }

        // If session hasn't activated yet, queue this sync for later
        guard isActivated else {
            pendingSync = { [weak self] in
                self?.syncSchedule(
                    tasks: tasks, streak: streak, quoteText: quoteText, quoteAuthor: quoteAuthor,
                    compassScores: compassScores, userName: userName, aiInsight: aiInsight,
                    completedCheckIns: completedCheckIns
                )
            }
            return
        }

        guard session.isPaired, session.isWatchAppInstalled else { return }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let dayEnd = calendar.safeDate(byAdding: .day, value: 1, to: dayStart)

        let todayTasks = tasks.filter { $0.date >= dayStart && $0.date < dayEnd }
            .sorted { $0.date < $1.date }

        let watchTasks = todayTasks.map { task in
            WatchScheduleData.WatchTask(
                id: task.id,
                title: task.title,
                date: task.date,
                priorityRaw: task.priorityRaw,
                categoryRaw: task.categoryRaw,
                done: task.done,
                isCalendarEvent: task.externalCalendarID != nil,
                recurrenceRaw: task.recurrenceRaw
            )
        }

        // Which slot is the user currently in? Single source of truth is
        // CheckInTime.slot(forHour:) — Watch and iOS must agree on the label.
        let hour = calendar.component(.hour, from: Date())
        let nextCheckIn: String? = CheckInTime.slot(forHour: hour).rawValue

        let data = WatchScheduleData(
            tasks: watchTasks,
            streakDays: streak,
            completedToday: todayTasks.filter(\.done).count,
            totalToday: todayTasks.count,
            quoteText: quoteText,
            quoteAuthor: quoteAuthor,
            nextCheckIn: nextCheckIn,
            updatedAt: Date(),
            bodyScore: compassScores?.body,
            mindScore: compassScores?.mind,
            heartScore: compassScores?.heart,
            spiritScore: compassScores?.spirit,
            userName: userName,
            aiInsight: aiInsight,
            completedCheckIns: completedCheckIns
        )

        var context = data.toDictionary()
        // Include API key in context so Watch always has it
        let keychain = KeychainService()
        if let apiKey = keychain.anthropicAPIKey(), !apiKey.isEmpty {
            context["apiKey"] = apiKey
        }
        // Include text size preference
        context["textSize"] = TextSizeManager.shared.selectedSize.rawValue
        try? session.updateApplicationContext(context)
    }
}

// MARK: - WCSessionDelegate

extension WatchSyncManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            Task { @MainActor in
                self.isActivated = true
                self.pendingSync?()
                self.pendingSync = nil
            }
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// Handle Watch requesting a fresh schedule update, toggling a task, or adding a task
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["request"] as? String == "scheduleUpdate" {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchRequestedUpdate, object: nil)
            }
        }
        if let taskID = message["toggleTask"] as? String {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchToggledTask, object: nil, userInfo: ["taskID": taskID])
            }
        }
        if message["addTask"] as? Bool == true {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchAddedTask, object: nil, userInfo: message)
            }
        }
        if message["quickCheckIn"] as? Bool == true {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchQuickCheckIn, object: nil, userInfo: message)
            }
        }
        if let taskID = message["deleteTask"] as? String {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchDeletedTask, object: nil, userInfo: ["taskID": taskID])
            }
        }
    }

    /// Handle queued messages sent via transferUserInfo (when iPhone wasn't reachable)
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let taskID = userInfo["toggleTask"] as? String {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchToggledTask, object: nil, userInfo: ["taskID": taskID])
            }
        }
        if userInfo["addTask"] as? Bool == true {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchAddedTask, object: nil, userInfo: userInfo)
            }
        }
        if userInfo["quickCheckIn"] as? Bool == true {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchQuickCheckIn, object: nil, userInfo: userInfo)
            }
        }
        if let taskID = userInfo["deleteTask"] as? String {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchDeletedTask, object: nil, userInfo: ["taskID": taskID])
            }
        }
    }
}

extension Notification.Name {
    static let watchRequestedUpdate = Notification.Name("watchRequestedUpdate")
    static let watchToggledTask = Notification.Name("watchToggledTask")
    static let watchAddedTask = Notification.Name("watchAddedTask")
    static let watchDeletedTask = Notification.Name("watchDeletedTask")
    static let watchQuickCheckIn = Notification.Name("watchQuickCheckIn")
}
