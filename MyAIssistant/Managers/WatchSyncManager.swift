import Foundation
import WatchConnectivity

/// Manages iPhone → Watch data sync via WatchConnectivity.
/// Sends schedule snapshots to the Watch app whenever tasks change.
@MainActor
final class WatchSyncManager: NSObject, ObservableObject {
    static let shared = WatchSyncManager()
    private var session: WCSession?

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
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }
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
        quoteAuthor: String?
    ) {
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }

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

        // Determine next check-in
        let hour = calendar.component(.hour, from: Date())
        let nextCheckIn: String? = {
            if hour < 8 { return "Morning" }
            if hour < 13 { return "Midday" }
            if hour < 18 { return "Afternoon" }
            if hour < 22 { return "Night" }
            return nil
        }()

        let data = WatchScheduleData(
            tasks: watchTasks,
            streakDays: streak,
            completedToday: todayTasks.filter(\.done).count,
            totalToday: todayTasks.count,
            quoteText: quoteText,
            quoteAuthor: quoteAuthor,
            nextCheckIn: nextCheckIn,
            updatedAt: Date()
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
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// Handle Watch requesting a fresh schedule update or toggling a task
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
    }

    /// Handle queued task toggles sent via transferUserInfo (when iPhone wasn't reachable)
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let taskID = userInfo["toggleTask"] as? String {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchToggledTask, object: nil, userInfo: ["taskID": taskID])
            }
        }
    }
}

extension Notification.Name {
    static let watchRequestedUpdate = Notification.Name("watchRequestedUpdate")
    static let watchToggledTask = Notification.Name("watchToggledTask")
}
