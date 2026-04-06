import Foundation
import Observation
import SwiftData
import WidgetKit

@Observable @MainActor
final class CheckInBehaviorEngine {
    private let modelContext: ModelContext

    private(set) var activeSuggestion: CheckInSuggestion?
    private(set) var windowInsights: [WindowInsight] = []

    struct WindowInsight: Identifiable {
        let windowRaw: String
        let displayTitle: String
        let icon: String
        let completionRate: Double
        let averageTime: String
        let consecutiveSkips: Int
        let isEnabled: Bool

        var id: String { windowRaw }
        var completionPercentage: Int { Int((completionRate * 100).rounded()) }
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Seeding

    func seedDefaultPreferencesIfNeeded() {
        let descriptor = FetchDescriptor<CheckInPreference>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        for pref in CheckInPreference.defaultPreferences() {
            modelContext.insert(pref)
        }
        modelContext.safeSave()
        syncWidgetData()
    }

    // MARK: - Active Preferences

    func activePreferences() -> [CheckInPreference] {
        let descriptor = FetchDescriptor<CheckInPreference>(
            predicate: #Predicate { $0.isEnabled },
            sortBy: [SortDescriptor(\CheckInPreference.customHour)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func allPreferences() -> [CheckInPreference] {
        let descriptor = FetchDescriptor<CheckInPreference>(
            sortBy: [SortDescriptor(\CheckInPreference.customHour)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Recalculation

    func recalculateIfNeeded() {
        let preferences = allPreferences()
        guard !preferences.isEmpty else { return }

        let today = Calendar.current.startOfDay(for: Date())

        for pref in preferences where pref.isEnabled {
            let behavior = fetchOrCreateBehavior(for: pref.windowRaw)

            // Skip if already calculated today
            if Calendar.current.isDate(behavior.lastCalculatedDate, inSameDayAs: today) {
                continue
            }

            recalculateWindow(behavior: behavior, preference: pref)
        }

        modelContext.safeSave()
        refreshInsights()
        generateSuggestions()
    }

    private func recalculateWindow(behavior: CheckInBehavior, preference: CheckInPreference) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let windowStart = calendar.date(byAdding: .day, value: -AppConstants.behaviorWindowDays, to: today)!
        let windowRaw = preference.windowRaw

        // Fetch completed check-ins for this window in the rolling period
        let descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { record in
                record.timeSlotRaw == windowRaw &&
                record.completed == true &&
                record.date >= windowStart
            }
        )
        let completedRecords = (try? modelContext.fetch(descriptor)) ?? []

        // Calculate stats
        let opportunities = AppConstants.behaviorWindowDays
        let completedCount = completedRecords.count

        behavior.totalCompleted = completedCount
        behavior.totalOpportunities = opportunities
        behavior.completionRate = opportunities > 0 ? Double(completedCount) / Double(opportunities) : 0

        // Average completion time
        if !completedRecords.isEmpty {
            var totalMinutesSinceMidnight = 0
            for record in completedRecords {
                let hour = calendar.component(.hour, from: record.date)
                let minute = calendar.component(.minute, from: record.date)
                totalMinutesSinceMidnight += hour * 60 + minute
            }
            let avgMinutes = totalMinutesSinceMidnight / completedRecords.count
            behavior.averageCompletionHour = avgMinutes / 60
            behavior.averageCompletionMinute = avgMinutes % 60

            behavior.lastCompletedDate = completedRecords
                .max(by: { $0.date < $1.date })?.date
        }

        // Consecutive skips — count backward from yesterday
        behavior.consecutiveSkips = calculateConsecutiveSkips(
            windowRaw: windowRaw,
            from: calendar.date(byAdding: .day, value: -1, to: today)!
        )

        behavior.lastCalculatedDate = Date()
    }

    private func calculateConsecutiveSkips(windowRaw: String, from startDate: Date) -> Int {
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .day, value: -AppConstants.behaviorWindowDays, to: startDate)!

        // Single fetch: all completed check-ins for this window in the rolling period
        let descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { record in
                record.timeSlotRaw == windowRaw &&
                record.completed == true &&
                record.date >= windowStart
            }
        )
        let records = (try? modelContext.fetch(descriptor)) ?? []

        // Build set of days that had completions
        let completedDays = Set(records.map { calendar.startOfDay(for: $0.date) })

        // Count backward from startDate until we hit a day with a completion
        var skips = 0
        var checkDate = startDate
        for _ in 0..<AppConstants.behaviorWindowDays {
            let day = calendar.startOfDay(for: checkDate)
            if completedDays.contains(day) {
                break
            }
            skips += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }

        return skips
    }

    // MARK: - Behavior Record Management

    private func fetchOrCreateBehavior(for windowRaw: String) -> CheckInBehavior {
        let descriptor = FetchDescriptor<CheckInBehavior>(
            predicate: #Predicate { $0.windowRaw == windowRaw }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        let new = CheckInBehavior(windowRaw: windowRaw)
        modelContext.insert(new)
        return new
    }

    // MARK: - Suggestion Generation

    private func generateSuggestions() {
        // Only generate if no pending suggestion
        let pendingDescriptor = FetchDescriptor<CheckInSuggestion>(
            predicate: #Predicate { $0.statusRaw == "pending" }
        )
        let pendingCount = (try? modelContext.fetchCount(pendingDescriptor)) ?? 0
        guard pendingCount == 0 else {
            refreshActiveSuggestion()
            return
        }

        let preferences = allPreferences().filter(\.isEnabled)

        for pref in preferences {
            let behavior = fetchOrCreateBehavior(for: pref.windowRaw)

            // Check for disable suggestion
            if behavior.completionRate < AppConstants.disableThreshold &&
               behavior.consecutiveSkips >= AppConstants.behaviorWindowDays {
                if !hasCooldownSuggestion(type: .disableWindow, windowRaw: pref.windowRaw) {
                    let completed = behavior.totalCompleted
                    let suggestion = CheckInSuggestion(
                        type: .disableWindow,
                        targetWindowRaw: pref.windowRaw,
                        reason: "You've completed \(pref.displayTitle) only \(completed) time\(completed == 1 ? "" : "s") in the last \(AppConstants.behaviorWindowDays) days. Want to skip it?"
                    )
                    modelContext.insert(suggestion)
                    modelContext.safeSave()
                    refreshActiveSuggestion()
                    return
                }
            }

            // Check for time adjustment suggestion
            if behavior.totalCompleted >= 5 {
                let scheduledMinutes = pref.customHour * 60 + pref.customMinute
                let actualMinutes = behavior.averageCompletionHour * 60 + behavior.averageCompletionMinute
                let drift = abs(scheduledMinutes - actualMinutes)

                if drift > AppConstants.quietAdjustMaxMinutes {
                    // Large drift — suggest adjustment
                    if !hasCooldownSuggestion(type: .adjustTime, windowRaw: pref.windowRaw) {
                        let suggestion = CheckInSuggestion(
                            type: .adjustTime,
                            targetWindowRaw: pref.windowRaw,
                            reason: "You usually check in around \(behavior.averageTimeString) instead of \(pref.scheduledTimeString). Adjust?",
                            suggestedHour: behavior.averageCompletionHour,
                            suggestedMinute: behavior.averageCompletionMinute
                        )
                        modelContext.insert(suggestion)
                        modelContext.safeSave()
                        refreshActiveSuggestion()
                        return
                    }
                } else if drift >= AppConstants.timeDriftThresholdMinutes {
                    // Small drift — quietly adjust
                    quietlyAdjustTime(preference: pref, behavior: behavior)
                }
            }
        }

        // Check for organic check-in clusters
        checkForOrganicClusters(existingPreferences: preferences)
        refreshActiveSuggestion()
    }

    private func quietlyAdjustTime(preference: CheckInPreference, behavior: CheckInBehavior) {
        let newHour = behavior.averageCompletionHour
        let newMinute = behavior.averageCompletionMinute

        // Ensure no conflict with other windows
        let others = activePreferences().filter { $0.windowRaw != preference.windowRaw }
        let newMinutesSinceMidnight = newHour * 60 + newMinute

        for other in others {
            let otherMinutes = other.customHour * 60 + other.customMinute
            if abs(newMinutesSinceMidnight - otherMinutes) < AppConstants.minWindowSpacingMinutes {
                return // Would conflict — skip adjustment
            }
        }

        preference.customHour = newHour
        preference.customMinute = newMinute
        modelContext.safeSave()
    }

    private func checkForOrganicClusters(existingPreferences: [CheckInPreference]) {
        let calendar = Calendar.current
        let windowStart = calendar.date(
            byAdding: .day,
            value: -AppConstants.behaviorWindowDays,
            to: calendar.startOfDay(for: Date())
        )!

        let descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { record in
                record.completed == true && record.date >= windowStart
            }
        )
        let allRecords = (try? modelContext.fetch(descriptor)) ?? []

        // Group check-ins by hour
        var hourCounts: [Int: Int] = [:]
        let scheduledHours = Set(existingPreferences.map(\.customHour))

        for record in allRecords {
            let hour = calendar.component(.hour, from: record.date)
            // Only count if not within 1 hour of a scheduled window
            let isNearScheduled = scheduledHours.contains(where: { abs($0 - hour) <= 1 })
            if !isNearScheduled {
                hourCounts[hour, default: 0] += 1
            }
        }

        // Find clusters that exceed threshold
        if let (hour, count) = hourCounts.max(by: { $0.value < $1.value }),
           count >= AppConstants.organicClusterMinCount {
            if !hasCooldownSuggestion(type: .addWindow, windowRaw: nil) {
                let formatter = DateFormatter()
                formatter.dateFormat = "h a"
                var components = DateComponents()
                components.hour = hour
                let timeStr = formatter.string(from: calendar.date(from: components) ?? Date())

                let suggestion = CheckInSuggestion(
                    type: .addWindow,
                    reason: "You've checked in around \(timeStr) about \(count) times recently. Add a regular check-in there?",
                    suggestedHour: hour,
                    suggestedMinute: 0
                )
                modelContext.insert(suggestion)
                modelContext.safeSave()
            }
        }
    }

    private func hasCooldownSuggestion(type: SuggestionType, windowRaw: String?) -> Bool {
        let typeStr = type.rawValue
        let descriptor = FetchDescriptor<CheckInSuggestion>(
            predicate: #Predicate { suggestion in
                suggestion.typeRaw == typeStr &&
                suggestion.statusRaw == "dismissed"
            }
        )
        let dismissed = (try? modelContext.fetch(descriptor)) ?? []

        return dismissed.contains { suggestion in
            // Match window if specified
            if let windowRaw, suggestion.targetWindowRaw != windowRaw { return false }
            // Check cooldown
            guard let until = suggestion.dismissedUntil else { return false }
            return Date() < until
        }
    }

    // MARK: - Suggestion Actions

    func applySuggestion(_ suggestion: CheckInSuggestion) {
        switch suggestion.type {
        case .disableWindow:
            if let windowRaw = suggestion.targetWindowRaw,
               let pref = findPreference(windowRaw: windowRaw) {
                pref.isEnabled = false
            }

        case .adjustTime:
            if let windowRaw = suggestion.targetWindowRaw,
               let pref = findPreference(windowRaw: windowRaw),
               let hour = suggestion.suggestedHour {
                pref.customHour = hour
                pref.customMinute = suggestion.suggestedMinute ?? 0
            }

        case .addWindow:
            if let hour = suggestion.suggestedHour {
                let newPref = CheckInPreference(
                    windowRaw: "Custom-\(UUID().uuidString)",
                    customHour: hour,
                    customMinute: suggestion.suggestedMinute ?? 0,
                    customTitle: suggestion.suggestedTimeString.map { "\($0) Check-in" },
                    isSystemGenerated: false
                )
                modelContext.insert(newPref)
            }
        }

        suggestion.statusRaw = SuggestionStatus.accepted.rawValue
        modelContext.safeSave()
        activeSuggestion = nil
        syncWidgetData()
    }

    func dismissSuggestion(_ suggestion: CheckInSuggestion) {
        suggestion.statusRaw = SuggestionStatus.dismissed.rawValue
        suggestion.dismissedUntil = Calendar.current.date(
            byAdding: .day,
            value: AppConstants.suggestionCooldownDays,
            to: Date()
        )
        modelContext.safeSave()
        activeSuggestion = nil
    }

    // MARK: - Record Completion (called from CheckInDetailView)

    func recordCompletion(window: CheckInTime) {
        let behavior = fetchOrCreateBehavior(for: window.rawValue)
        behavior.lastCompletedDate = Date()

        let hour = Calendar.current.component(.hour, from: Date())
        let minute = Calendar.current.component(.minute, from: Date())

        // Update running average (simple weighted blend)
        if behavior.totalCompleted > 0 {
            let currentAvg = behavior.averageCompletionHour * 60 + behavior.averageCompletionMinute
            let newMinutes = hour * 60 + minute
            let blended = (currentAvg * behavior.totalCompleted + newMinutes) / (behavior.totalCompleted + 1)
            behavior.averageCompletionHour = blended / 60
            behavior.averageCompletionMinute = blended % 60
        } else {
            behavior.averageCompletionHour = hour
            behavior.averageCompletionMinute = minute
        }

        behavior.totalCompleted += 1
        behavior.consecutiveSkips = 0
        modelContext.safeSave()
    }

    // MARK: - Helpers

    private func findPreference(windowRaw: String) -> CheckInPreference? {
        let descriptor = FetchDescriptor<CheckInPreference>(
            predicate: #Predicate { $0.windowRaw == windowRaw }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Sync enabled windows to App Group UserDefaults for the widget.
    func syncWidgetData() {
        let prefs = activePreferences()
        let windows = prefs.map { pref in
            WidgetCheckInWindow(
                name: pref.displayTitle,
                hour: pref.customHour,
                minute: pref.customMinute,
                greeting: pref.checkInTime?.greeting ?? "Time for a check-in!"
            )
        }
        if let data = try? JSONEncoder().encode(windows) {
            UserDefaults(suiteName: AppConstants.appGroupID)?.set(data, forKey: "enabledCheckInWindows")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refreshActiveSuggestion() {
        let descriptor = FetchDescriptor<CheckInSuggestion>(
            predicate: #Predicate { $0.statusRaw == "pending" },
            sortBy: [SortDescriptor(\CheckInSuggestion.createdAt, order: .reverse)]
        )
        var limited = descriptor
        limited.fetchLimit = 1
        activeSuggestion = try? modelContext.fetch(limited).first
    }

    private func refreshInsights() {
        let preferences = allPreferences()
        windowInsights = preferences.map { pref in
            let behavior = fetchOrCreateBehavior(for: pref.windowRaw)
            return WindowInsight(
                windowRaw: pref.windowRaw,
                displayTitle: pref.displayTitle,
                icon: pref.displayIcon,
                completionRate: behavior.completionRate,
                averageTime: behavior.averageTimeString,
                consecutiveSkips: behavior.consecutiveSkips,
                isEnabled: pref.isEnabled
            )
        }
    }
}
