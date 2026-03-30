#if os(watchOS)
import Foundation
import WatchConnectivity
import SwiftUI
import WidgetKit
import Security

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
