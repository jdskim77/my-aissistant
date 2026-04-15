#if os(watchOS)
import Foundation
import WatchConnectivity
import SwiftUI
import WidgetKit
import Security

// MARK: - Engine / Reusable (with Thrivn-shaped payload type)
//
// Watch-side counterpart to iOS WatchSyncManager. Receives application
// context updates from iPhone, decodes into `WatchScheduleData`, exposes
// it to views + complications, and forwards Watch-originated actions back
// to iPhone (task toggles, quick check-ins, voice chat triggers).
//
// REUSABLE (keep in fork):
//   - Singleton + WCSessionDelegate boilerplate
//   - applicationContext receive + decode flow
//   - sendMessage paths for Watch → iPhone actions
//   - WidgetKit reload after data updates
//   - shouldOpenVoiceChat flag for Action Button intent
//
// ⚠️ THRIVN-SPECIFIC — REVISIT IN FORK:
//   - The payload type `WatchScheduleData` (see its own header — its
//     bodyScore/mindScore/heartScore/spiritScore fields are Thrivn).
//   - The "quickCheckIn" message format ties to Thrivn's check-in model.
//
// Dependencies: WatchConnectivity, WidgetKit, WatchScheduleData (shared
// payload struct), Security (for forwarded API key).
// Watch-compatible: yes (this IS the Watch target).

/// Receives schedule data from iPhone and makes it available to Watch views + complications.
@Observable
class WatchConnectivityManager: NSObject, WCSessionDelegate {
    /// Singleton — used by Action Button intent and passed to views.
    static let shared = WatchConnectivityManager()

    var scheduleData: WatchScheduleData?
    var shouldOpenVoiceChat = false
    private(set) var apiKey: String?

    override init() {
        super.init()
        loadFromCache()
        loadAPIKeyFromCache()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    var todayTasks: [WatchScheduleData.WatchTask] {
        scheduleData?.tasks ?? []
    }

    var activeTasks: [WatchScheduleData.WatchTask] {
        todayTasks.filter { !$0.done }
    }

    var completedTasks: [WatchScheduleData.WatchTask] {
        todayTasks.filter(\.done)
    }

    var completionFraction: Double {
        guard let data = scheduleData, data.totalToday > 0 else { return 0 }
        return Double(data.completedToday) / Double(data.totalToday)
    }

    var upNextTask: WatchScheduleData.WatchTask? {
        let now = Date()
        return activeTasks.first { $0.date >= now } ?? activeTasks.first
    }

    func requestUpdate() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["request": "scheduleUpdate"], replyHandler: nil)
    }

    /// Send a new task to iPhone for creation.
    /// Send a quick check-in (mood + energy) to iPhone for processing.
    func sendCheckIn(_ message: [String: Any]) {
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil)
        } else {
            WCSession.default.transferUserInfo(message)
        }

        // Optimistically update completed check-ins
        if let slot = message["timeSlot"] as? String, var data = scheduleData {
            var completed = data.completedCheckIns ?? []
            if !completed.contains(slot) { completed.append(slot) }
            let updated = WatchScheduleData(
                tasks: data.tasks,
                streakDays: data.streakDays,
                completedToday: data.completedToday,
                totalToday: data.totalToday,
                quoteText: data.quoteText,
                quoteAuthor: data.quoteAuthor,
                nextCheckIn: nextCheckInAfter(slot),
                updatedAt: Date(),
                bodyScore: data.bodyScore,
                mindScore: data.mindScore,
                heartScore: data.heartScore,
                spiritScore: data.spiritScore,
                userName: data.userName,
                aiInsight: data.aiInsight,
                completedCheckIns: completed
            )
            persistAndUpdate(updated)
        }
    }

    private func nextCheckInAfter(_ slot: String) -> String? {
        let order = ["Morning", "Midday", "Afternoon", "Night"]
        guard let idx = order.firstIndex(of: slot) else { return nil }
        let completed = scheduleData?.completedCheckIns ?? []
        for i in (idx + 1)..<order.count {
            if !completed.contains(order[i]) { return order[i] }
        }
        return nil // All done
    }

    /// Send a new task to iPhone for creation.
    func addTask(title: String, priority: String, date: Date, hasTime: Bool, dimensions: String? = nil) {
        var message: [String: Any] = [
            "addTask": true,
            "title": title,
            "priority": priority,
            "date": date.timeIntervalSince1970,
            "hasTime": hasTime
        ]
        if let dimensions { message["dimensions"] = dimensions }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil)
        } else {
            WCSession.default.transferUserInfo(message)
        }

        // Optimistically add to local schedule
        if var data = scheduleData {
            let newTask = WatchScheduleData.WatchTask(
                id: UUID().uuidString,
                title: title,
                date: date,
                priorityRaw: priority,
                categoryRaw: "Personal",
                done: false,
                isCalendarEvent: false,
                recurrenceRaw: nil
            )
            let updated = WatchScheduleData(
                tasks: (data.tasks + [newTask]).sorted { $0.date < $1.date },
                streakDays: data.streakDays,
                completedToday: data.completedToday,
                totalToday: data.totalToday + 1,
                quoteText: data.quoteText,
                quoteAuthor: data.quoteAuthor,
                nextCheckIn: data.nextCheckIn,
                updatedAt: Date(),
                bodyScore: data.bodyScore, mindScore: data.mindScore,
                heartScore: data.heartScore, spiritScore: data.spiritScore,
                userName: data.userName, aiInsight: data.aiInsight,
                completedCheckIns: data.completedCheckIns
            )
            persistAndUpdate(updated)
        }
    }

    /// Delete a task from both Watch (optimistic) and iPhone.
    func deleteTask(_ taskID: String) {
        // Optimistically remove from local schedule
        if let data = scheduleData,
           let taskToDelete = data.tasks.first(where: { $0.id == taskID }) {
            let updated = WatchScheduleData(
                tasks: data.tasks.filter { $0.id != taskID },
                streakDays: data.streakDays,
                completedToday: taskToDelete.done ? max(0, data.completedToday - 1) : data.completedToday,
                totalToday: max(0, data.totalToday - 1),
                quoteText: data.quoteText,
                quoteAuthor: data.quoteAuthor,
                nextCheckIn: data.nextCheckIn,
                updatedAt: Date(),
                bodyScore: data.bodyScore, mindScore: data.mindScore,
                heartScore: data.heartScore, spiritScore: data.spiritScore,
                userName: data.userName, aiInsight: data.aiInsight,
                completedCheckIns: data.completedCheckIns
            )
            persistAndUpdate(updated)
        }

        // Send to iPhone
        let message: [String: Any] = ["deleteTask": taskID]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil)
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }

    /// Send a task completion toggle to the iPhone for processing.
    func toggleTaskCompletion(_ taskID: String) {
        // Optimistically update local state
        if var data = scheduleData {
            let updatedTasks = data.tasks.map { task -> WatchScheduleData.WatchTask in
                guard task.id == taskID else { return task }
                return WatchScheduleData.WatchTask(
                    id: task.id,
                    title: task.title,
                    date: task.date,
                    priorityRaw: task.priorityRaw,
                    categoryRaw: task.categoryRaw,
                    done: !task.done,
                    isCalendarEvent: task.isCalendarEvent,
                    recurrenceRaw: task.recurrenceRaw
                )
            }
            let toggled = updatedTasks.first { $0.id == taskID }
            let completedDelta = (toggled?.done == true) ? 1 : -1
            let updated = WatchScheduleData(
                tasks: updatedTasks,
                streakDays: data.streakDays,
                completedToday: max(0, data.completedToday + completedDelta),
                totalToday: data.totalToday,
                quoteText: data.quoteText,
                quoteAuthor: data.quoteAuthor,
                nextCheckIn: data.nextCheckIn,
                updatedAt: Date(),
                bodyScore: data.bodyScore, mindScore: data.mindScore,
                heartScore: data.heartScore, spiritScore: data.spiritScore,
                userName: data.userName, aiInsight: data.aiInsight,
                completedCheckIns: data.completedCheckIns
            )
            persistAndUpdate(updated)
        }

        // Send to iPhone
        let message: [String: Any] = ["toggleTask": taskID]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil)
        } else {
            // Use transferUserInfo as fallback for when iPhone isn't reachable
            WCSession.default.transferUserInfo(message)
        }
    }

    // MARK: - Persistence

    private static let apiKeyAccount = "com.myaissistant.watch-api-key"

    private func extractAPIKey(from dict: [String: Any]) {
        if let key = dict["apiKey"] as? String, !key.isEmpty {
            self.apiKey = key
            saveAPIKeyToKeychain(key)
        }
    }

    private func loadAPIKeyFromCache() {
        apiKey = loadAPIKeyFromKeychain()
    }

    private func saveAPIKeyToKeychain(_ key: String) {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.apiKeyAccount
        ]
        SecItemDelete(query as CFDictionary)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.apiKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    private func loadAPIKeyFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            // Migrate from old UserDefaults storage if present
            if let old = UserDefaults.standard.string(forKey: "watchAPIKey") {
                saveAPIKeyToKeychain(old)
                UserDefaults.standard.removeObject(forKey: "watchAPIKey")
                return old
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func persistAndUpdate(_ data: WatchScheduleData) {
        self.scheduleData = data
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let encoded = try? encoder.encode(data) {
            UserDefaults.standard.set(encoded, forKey: "watchScheduleCache")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func loadFromCache() {
        guard let data = UserDefaults.standard.data(forKey: "watchScheduleCache") else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        scheduleData = try? decoder.decode(WatchScheduleData.self, from: data)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        DispatchQueue.main.async {
            self.extractAPIKey(from: context)
            if let data = WatchScheduleData.from(context: context) {
                self.persistAndUpdate(data)
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            self.extractAPIKey(from: applicationContext)
            if let data = WatchScheduleData.from(context: applicationContext) {
                self.persistAndUpdate(data)
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            self.extractAPIKey(from: message)
            if let data = WatchScheduleData.from(context: message) {
                self.persistAndUpdate(data)
            }
        }
    }
}

#endif
