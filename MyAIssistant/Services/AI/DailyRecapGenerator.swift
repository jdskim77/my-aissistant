import Foundation
import SwiftData
import os.log

/// Generates personalized AI insight messages after check-ins.
/// Uses Haiku for fast, cost-effective generation.
@MainActor
final class DailyRecapGenerator {
    private let modelContext: ModelContext
    private let keychainService: KeychainService

    // Injected managers for data assembly
    var patternEngine: PatternEngine?
    var balanceManager: BalanceManager?
    var taskManager: TaskManager?
    var chatManager: ChatManager?
    var habitManager: HabitManager?

    /// On-device crisis classifier. Runs over check-in notes (free-text
    /// user input) BEFORE the LLM call. If any note flags, the recap
    /// generation is skipped — we never feed crisis content to the model
    /// and we never let the model author the response back. This mirrors
    /// the chat-side gate in ChatManager.send. Per CLAUDE.md
    /// "crisis-safety-protocols": classifier-first, LLM-never for this
    /// boundary. Caller (CheckInDetailView) shows hardcoded SafeResourceCopy
    /// when generate() returns the safety sentinel.
    var crisisClassifier: CrisisClassifier?

    /// The conversation ID used for daily recap messages in the chat.
    static let conversationID = "daily-recap"

    /// UserDefaults key storing the timestamp (TimeInterval since 1970)
    /// of the last crisis-route fire. Used by the per-day safety latch
    /// to skip re-evaluating the same flagged note on every later
    /// check-in today. Implicitly cleared by the same-day check —
    /// yesterday's value is ignored (no explicit cleanup needed).
    static let crisisLatchKey = "dailyRecap.lastCrisisRouteAt"

    /// Returns the latch timestamp ONLY if it's from today (same calendar
    /// day). Returns nil if the stored value is from a prior day or was
    /// never set — in which case the gate evaluates every note as
    /// normal. The same-day check is what makes this a per-day latch
    /// rather than a permanent one.
    private func sameDayCrisisLatch() -> Date? {
        let interval = UserDefaults.standard.double(forKey: Self.crisisLatchKey)
        guard interval > 0 else { return nil }
        let date = Date(timeIntervalSince1970: interval)
        guard Calendar.current.isDateInToday(date) else { return nil }
        return date
    }

    init(modelContext: ModelContext, keychainService: KeychainService) {
        self.modelContext = modelContext
        self.keychainService = keychainService
    }

    // MARK: - Day Number

    /// How many days since the user's first-ever check-in. Day 1 = first day.
    func dayNumber() -> Int {
        let descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        guard let first = (try? modelContext.fetch(descriptor))?.first else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: first.date, to: Date()).day ?? 0
        return max(1, days + 1)
    }

    // MARK: - Generate Recap

    /// Discriminated result so callers can render safety-framed copy
    /// distinctly from LLM-generated insight copy WITHOUT reverse-engineering
    /// intent from string identity. The previous `String?` return forced
    /// `CheckInDetailView` to compare against `SafeResourceCopy.message()`
    /// to detect the safety route — fragile against any copy edit and
    /// against locale drift between the two call sites.
    enum RecapResult: Equatable {
        /// LLM-generated insight (or fallback content). Render as the
        /// normal recap card.
        case insight(String)
        /// Crisis gate fired. Render as safety-framed card with hotline
        /// link and no "Reply" affordance.
        case safety(String)

        /// Convenience for callers that just want the displayable text.
        var text: String {
            switch self {
            case .insight(let s), .safety(let s): return s
            }
        }
    }

    /// Generate and return a personalized daily recap result.
    /// Returns nil if generation fails (no API key, classifier missing,
    /// upstream error). The non-nil cases discriminate insight vs safety.
    func generate(
        currentTimeSlot: CheckInTime,
        userName: String?,
        subscriptionTier: SubscriptionTier
    ) async -> RecapResult? {
        let day = dayNumber()

        // Assemble today's check-in data
        let todaysCheckIns = fetchTodaysCheckIns()

        // Crisis precheck on free-text notes — runs through `AIGuardrail`
        // so the boundary is consistent with the chat path and the
        // task-parser path.
        //
        // **Relaxation note:** the prior implementation was fail-closed
        // (`guard let classifier = crisisClassifier else { return nil }`).
        // It now falls back to `AIGuardrail.defaultClassifier` when DI
        // is missing — intentional, because `defaultClassifier` is a
        // non-nil `KeywordCrisisClassifier()`. The safety floor is the
        // default classifier, not nil. The error log below preserves
        // the loud diagnostic so a missed DI wire still surfaces in
        // production.
        if crisisClassifier == nil {
            AppLogger.ai.error("DailyRecapGenerator: crisisClassifier missing — falling back to AIGuardrail.defaultClassifier")
            Breadcrumb.add(category: "ai", message: "Recap: classifier missing, default fallback")
        }
        let classifier = crisisClassifier ?? AIGuardrail.defaultClassifier

        // Per-day safety latch. Once safety has fired today, subsequent
        // recap calls on the SAME day skip any note older than the
        // latch timestamp. The user's morning crisis note doesn't keep
        // re-routing every later check-in to safety — that pattern felt
        // patronizing ("the app is stuck on the moment"). New notes
        // (newer than the latch) ARE still evaluated; if they flag, the
        // gate fires again and the latch advances. The latch is
        // implicitly cleared by the same-day check — yesterday's value
        // is ignored. User chose this behavior over the strict "always
        // re-route" alternative.
        let latch = sameDayCrisisLatch()

        // Build the candidate notes list (latch + non-empty filter) and
        // run the multi-text guardrail. First crisis match wins.
        let candidateNotes: [String] = todaysCheckIns.compactMap { entry in
            guard let text = entry.notes, !text.isEmpty else { return nil }
            // Skip notes older than the same-day latch — they already
            // triggered safety once. Notes equal to the latch timestamp
            // are also skipped (boundary inclusive on the prior side).
            if let latch, entry.date <= latch { return nil }
            return text
        }
        if case .block(let safetyText, _) = AIGuardrail.preflight(
            userTexts: candidateNotes,
            classifier: classifier,
            callSite: "recap"
        ) {
            // Persist symmetrically with the chat-side gate so the
            // safety reply is durable in the daily-recap conversation
            // (not just transient state on the view that triggered it).
            // Without this, dismissing the check-in sheet drops the
            // record of what the safety route showed — and downstream
            // dedup (`fetchRecentRecapTopics`) loses signal too.
            chatManager?.insertLocalMessage(
                role: .assistant,
                content: safetyText,
                conversationID: Self.conversationID,
                isSafetyResource: true
            )
            // Advance the latch so subsequent calls today skip this
            // (and any older) flagged note. Stored as a TimeInterval
            // so UserDefaults serializes a stable value.
            UserDefaults.standard.set(Date().timeIntervalSince1970,
                                      forKey: Self.crisisLatchKey)
            return .safety(safetyText)
        }

        // Assemble task stats
        let todayTasks = taskManager?.todayTasks() ?? []
        let completedToday = todayTasks.filter { $0.done }.count
        let totalToday = todayTasks.count

        // Pattern stats
        let streak = patternEngine?.currentStreak() ?? 0
        let completionRate = patternEngine?.completionRate() ?? 0
        let moodTrend = formatMoodTrend()

        // Balance
        let balanceSummary = balanceManager?.balanceSummaryForAI() ?? ""

        // Previous recap topics (to avoid repetition)
        let previousTopics = fetchRecentRecapTopics(last: 3)

        // User focus preference
        let focusPreference = UserDefaults.standard.string(forKey: "dailyRecap_userFocusPreference")

        // Active habits status
        let habitSummary = fetchHabitSummary()

        let prompt = AIPromptBuilder.dailyRecapPrompt(
            dayNumber: day,
            currentTimeSlot: currentTimeSlot.rawValue,
            userName: userName,
            userFocusPreference: focusPreference,
            // Strip the date field — the prompt builder doesn't need it
            // (it's only used by the gate's per-day latch above). Keeps
            // the prompt-builder API surface narrow.
            todaysCheckIns: todaysCheckIns.map {
                (slot: $0.slot, mood: $0.mood, energy: $0.energy, notes: $0.notes)
            },
            tasksCompletedToday: completedToday,
            tasksTotalToday: totalToday,
            streak: streak,
            completionRate: completionRate,
            balanceSummary: balanceSummary,
            recentMoodTrend: moodTrend,
            previousRecapTopics: previousTopics,
            habitSummary: habitSummary
        )

        do {
            // Use the lightweight model for fast, cheap generation
            let provider = try AIProviderFactory.provider(
                for: subscriptionTier,
                useCase: .checkIn,  // Uses Haiku — fast and cheap
                keychain: keychainService
            )

            let response = try await provider.sendMessage(
                userMessage: "Generate my daily recap.",
                conversationHistory: [],
                systemPromptStable: prompt,
                systemPromptVolatile: ""
            )

            let recap = response.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            // Save to chat history for continuity
            chatManager?.insertLocalMessage(
                role: .assistant,
                content: recap,
                conversationID: Self.conversationID
            )

            AppLogger.ai.info("Daily recap generated: day \(day, privacy: .public), \(recap.count, privacy: .public) chars")
            Breadcrumb.add(category: "ai", message: "Daily recap generated (day \(day))")

            return .insight(recap)
        } catch {
            AppLogger.ai.error("Daily recap generation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Data Assembly

    private func fetchTodaysCheckIns() -> [(slot: String, mood: Int, energy: Int, notes: String?, date: Date)] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start

        var descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { $0.completed && $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        descriptor.fetchLimit = 10

        let records = (try? modelContext.fetch(descriptor)) ?? []
        return records.map { record in
            (
                slot: record.timeSlotRaw,
                mood: record.mood ?? 3,
                energy: record.energyLevel ?? 3,
                notes: record.notes,
                date: record.date
            )
        }
    }

    private func formatMoodTrend() -> String {
        guard let trend = patternEngine?.moodTrend(days: 7), !trend.isEmpty else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return trend.map { point in
            "\(formatter.string(from: point.date)): mood \(String(format: "%.1f", point.mood))"
        }.joined(separator: ", ")
    }

    private func fetchHabitSummary() -> String {
        var descriptor = FetchDescriptor<HabitItem>(
            predicate: #Predicate { $0.archivedAt == nil }
        )
        descriptor.fetchLimit = 20
        let habits = (try? modelContext.fetch(descriptor)) ?? []
        guard !habits.isEmpty else { return "" }

        return habits.map { habit in
            let completedToday = habit.isCompletedOn(Date())
            let streak = habit.currentStreak()
            let rate = Int(habit.completionRate(days: 7) * 100)
            let daysSince = daysSinceLastCompletion(habit)
            var line = "\(habit.icon) \(habit.title): "
            if completedToday {
                line += "done today"
            } else if let days = daysSince {
                line += "\(days) day\(days == 1 ? "" : "s") since last"
            } else {
                line += "never completed"
            }
            line += ", streak \(streak), 7-day rate \(rate)%"
            return line
        }.joined(separator: "\n")
    }

    private func daysSinceLastCompletion(_ habit: HabitItem) -> Int? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for offset in 1...90 {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { break }
            if habit.isCompletedOn(date) { return offset }
        }
        return nil
    }

    private func fetchRecentRecapTopics(last count: Int) -> [String] {
        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.conversationID == "daily-recap" && $0.roleRaw == "assistant" },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = count

        let messages = (try? modelContext.fetch(descriptor)) ?? []
        // Extract a brief topic hint from each message (first 80 chars)
        return messages.map { String($0.content.prefix(80)) }
    }
}
