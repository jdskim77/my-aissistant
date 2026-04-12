import Foundation
import SwiftUI

@Observable
@MainActor
final class GreetingManager {
    var currentGreeting: String = ""
    var isShowingGreeting: Bool = false

    private static let cooldownInterval: TimeInterval = 3600 // 1 hour
    private static let usedOpenersKey = "usedOpenersToday"
    private static let usedOpenersDateKey = "usedOpenersDate"
    private static let dismissedUntilKey = "greetingDismissedUntil"

    /// Generate a contextual greeting if the cooldown has elapsed.
    /// Returns `true` if a fresh greeting was generated, `false` if the cached one was restored.
    /// Respects user dismissal — won't re-show until the cooldown expires after dismissal.
    @discardableResult
    func generateGreetingIfNeeded(
        todayTaskCount: Int,
        completedTodayCount: Int,
        highPriorityTitles: [String],
        completionRate: Int,
        streak: Int
    ) -> Bool {
        let now = Date()

        // Respect user dismissal — don't re-show until the dismissed-until time
        let dismissedUntil = UserDefaults.standard.double(forKey: Self.dismissedUntilKey)
        if dismissedUntil > 0 && now.timeIntervalSince1970 < dismissedUntil {
            // User dismissed this greeting — restore text but keep hidden
            let cached = UserDefaults.standard.string(forKey: AppConstants.lastGreetingTextKey) ?? ""
            if !cached.isEmpty { currentGreeting = cached }
            return false
        }

        let lastGreeted = UserDefaults.standard.double(forKey: AppConstants.lastGreetedTimestampKey)
        let lastDate = Date(timeIntervalSince1970: lastGreeted)

        // Within cooldown — restore cached greeting
        if now.timeIntervalSince(lastDate) < Self.cooldownInterval {
            let cached = UserDefaults.standard.string(forKey: AppConstants.lastGreetingTextKey) ?? ""
            if !cached.isEmpty {
                currentGreeting = cached
                isShowingGreeting = true
                return false
            }
        }

        // Generate fresh greeting, excluding previously used openers today
        let usedOpeners = loadUsedOpenersToday()

        let result = VariedGreetingBuilder.greetingWithOpener(
            todayTaskCount: todayTaskCount,
            completedTodayCount: completedTodayCount,
            highPriorityTitles: highPriorityTitles,
            completionRate: completionRate,
            streak: streak,
            excludeOpeners: usedOpeners
        )

        currentGreeting = result.text
        isShowingGreeting = true

        // Clear any previous dismissal since this is a fresh greeting
        UserDefaults.standard.removeObject(forKey: Self.dismissedUntilKey)

        // Track the opener so it won't repeat today
        recordUsedOpener(result.opener)

        // Persist for cooldown check
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: AppConstants.lastGreetedTimestampKey)
        UserDefaults.standard.set(result.text, forKey: AppConstants.lastGreetingTextKey)

        return true
    }

    /// Dismiss the greeting. It won't reappear until the cooldown expires (1 hour).
    func dismissGreeting() {
        withAnimation(.easeOut(duration: 0.3)) {
            isShowingGreeting = false
        }
        // Prevent re-showing for the full cooldown period from now
        let dismissUntil = Date().timeIntervalSince1970 + Self.cooldownInterval
        UserDefaults.standard.set(dismissUntil, forKey: Self.dismissedUntilKey)
    }

    // MARK: - Used Opener Tracking

    /// Returns the set of opener phrases already shown today (instance method).
    func loadUsedOpenersToday() -> Set<String> {
        Self.loadUsedOpenersForToday()
    }

    /// Record an opener so it won't be repeated today (instance method).
    func recordUsedOpener(_ opener: String) {
        Self.recordUsedOpenerForToday(opener)
    }

    /// Returns the set of opener phrases already shown today (static, callable without instance).
    static func loadUsedOpenersForToday() -> Set<String> {
        let storedDate = UserDefaults.standard.string(forKey: usedOpenersDateKey) ?? ""
        let todayString = todayDateString()

        // Reset if it's a new day
        if storedDate != todayString {
            UserDefaults.standard.set(todayString, forKey: usedOpenersDateKey)
            UserDefaults.standard.set([String](), forKey: usedOpenersKey)
            return []
        }

        let stored = UserDefaults.standard.stringArray(forKey: usedOpenersKey) ?? []
        return Set(stored)
    }

    /// Record an opener so it won't be repeated today (static, callable without instance).
    static func recordUsedOpenerForToday(_ opener: String) {
        let todayString = todayDateString()
        UserDefaults.standard.set(todayString, forKey: usedOpenersDateKey)

        var stored = UserDefaults.standard.stringArray(forKey: usedOpenersKey) ?? []
        if !stored.contains(opener) {
            stored.append(opener)
        }
        UserDefaults.standard.set(stored, forKey: usedOpenersKey)
    }

    private static func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
