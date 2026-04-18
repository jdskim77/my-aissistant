import Foundation
import SwiftData
import SwiftUI
import UserNotifications
import os.log

// MARK: - ChatManager

@Observable @MainActor
final class ChatManager {
    private let modelContext: ModelContext

    // Dependencies injected after init (set by the app entry point or view)
    var taskManager: TaskManager?
    var patternEngine: PatternEngine?
    var balanceManager: BalanceManager?
    var keychainService: KeychainService = KeychainService()
    var calendarSyncManager: CalendarSyncManager?
    var usageGateManager: UsageGateManager?
    var subscriptionTier: SubscriptionTier = .free

    /// Re-entrancy guard. A double-tap on Send (or a fast tap from voice mode,
    /// or simultaneous Watch + iPhone) was firing two parallel API calls and
    /// — critically — running both gate checks BEFORE the first counter
    /// increment, so a free-tier user at 9/10 messages could pass two messages
    /// through and end up at 11. Now mutually exclusive: while one send is
    /// in flight, subsequent sends short-circuit immediately.
    private var isSending = false

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Conversation Management

    func loadMessages(for conversationID: String) -> [ChatMessage] {
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.conversationID == conversationID },
            sortBy: [SortDescriptor(\ChatMessage.timestamp)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Inserts a message into a conversation without going through the AI.
    /// Used by Task Builder, Watch, voice flows, and any feature that needs to
    /// post a local-only assistant or user message.
    @discardableResult
    func insertLocalMessage(role: MessageRole, content: String, conversationID: String) -> ChatMessage {
        let msg = ChatMessage(role: role, content: content, conversationID: conversationID)
        modelContext.insert(msg)
        modelContext.safeSave()
        return msg
    }

    func deleteConversation(_ conversationID: String) {
        let messages = loadMessages(for: conversationID)
        for message in messages {
            modelContext.delete(message)
        }
        modelContext.safeSave()
    }

    // MARK: - Greeting

    func insertGreetingMessage(conversationID: String) -> String {
        let todayTasks = taskManager?.todayTasks() ?? []
        let highPriority = taskManager?.highPriorityUpcoming(limit: 1) ?? []
        let usedOpeners = GreetingManager.loadUsedOpenersForToday()

        let result = VariedGreetingBuilder.greetingWithOpener(
            todayTaskCount: todayTasks.count,
            completedTodayCount: todayTasks.filter(\.done).count,
            highPriorityTitles: highPriority.map(\.title),
            completionRate: patternEngine?.completionRate() ?? 0,
            streak: patternEngine?.currentStreak() ?? 0,
            excludeOpeners: usedOpeners
        )

        GreetingManager.recordUsedOpenerForToday(result.opener)

        let greetingMessage = ChatMessage(
            role: .assistant,
            content: result.text,
            conversationID: conversationID
        )
        modelContext.insert(greetingMessage)
        modelContext.safeSave()

        return result.text
    }

    // MARK: - Send Message

    /// Result of sending a message, containing info the view needs for UI updates.
    struct SendResult {
        let displayText: String
        let calendarActions: [CalendarAction]
        let alarms: [ParsedAlarm]
        let hasError: Bool
        let errorMessage: String?
    }

    func sendMessage(
        _ text: String,
        conversationID: String
    ) async -> SendResult {
        // Re-entrancy guard. See `isSending` declaration for the rationale.
        // We're @MainActor isolated so this read/write pair is safe without a lock.
        guard !isSending else {
            return SendResult(
                displayText: "",
                calendarActions: [],
                alarms: [],
                hasError: true,
                errorMessage: "Still sending the previous message — please wait."
            )
        }
        isSending = true
        defer { isSending = false }

        // Enforce free tier chat limit
        if let gate = usageGateManager, !gate.canSendChat(tier: subscriptionTier) {
            return SendResult(
                displayText: "",
                calendarActions: [],
                alarms: [],
                hasError: true,
                errorMessage: "paywall"
            )
        }

        // Fetch prior history BEFORE inserting the new message to avoid duplicate
        let priorHistory = loadMessages(for: conversationID)

        let userMessage = ChatMessage(role: .user, content: text, conversationID: conversationID)
        modelContext.insert(userMessage)
        modelContext.safeSave()

        do {
            let provider = try AIProviderFactory.provider(
                for: subscriptionTier,
                useCase: .chat,
                keychain: keychainService
            )

            let enabledLinks = calendarSyncManager?.enabledCalendarLinks() ?? []
            let hasGoogle = enabledLinks.contains { $0.calendarSource == .google }
            let hasApple = enabledLinks.contains { $0.calendarSource == .apple }
                || calendarSyncManager?.appleCalendarAuthorized == true

            // Stable block (cached): identity, instructions, patterns, balance, tag formats.
            let systemPromptStable = AIPromptBuilder.chatSystemPromptStable(
                hasGoogleCalendar: hasGoogle,
                hasAppleCalendar: hasApple,
                patternInsights: patternEngine?.patternInsightsText() ?? "",
                balanceSummary: balanceManager?.balanceSummaryForAI() ?? ""
            )

            // Volatile block (not cached): today's date, schedule, stats, recent activity.
            let systemPromptVolatile = AIPromptBuilder.chatSystemPromptVolatile(
                scheduleSummary: taskManager?.scheduleSummary() ?? "",
                completionRate: patternEngine?.completionRate() ?? 0,
                streak: patternEngine?.currentStreak() ?? 0,
                activitySummary: patternEngine?.activitySummaryText() ?? "",
                habitSummary: buildHabitSummary()
            )

            let aiResponse = try await provider.sendMessage(
                userMessage: text,
                conversationHistory: Array(priorHistory.suffix(10)),
                systemPromptStable: systemPromptStable,
                systemPromptVolatile: systemPromptVolatile
            )

            let cacheRead = aiResponse.cacheReadInputTokens ?? 0
            let cacheHit = cacheRead > 0
            AppLogger.ai.info("AI response: in=\(aiResponse.inputTokens, privacy: .public) out=\(aiResponse.outputTokens, privacy: .public) cache=\(cacheHit ? "hit" : "miss", privacy: .public)")
            Breadcrumb.add(category: "ai", message: "Chat response: \(aiResponse.outputTokens) tokens")

            let parsed = parseResponseTags(from: aiResponse.content)

            let assistantMessage = ChatMessage(
                role: .assistant,
                content: parsed.displayText,
                conversationID: conversationID
            )
            modelContext.insert(assistantMessage)

            // Track usage (cache counters folded into effective input cost)
            usageGateManager?.recordChatMessage(
                inputTokens: aiResponse.inputTokens,
                outputTokens: aiResponse.outputTokens,
                cacheCreationTokens: aiResponse.cacheCreationInputTokens,
                cacheReadTokens: aiResponse.cacheReadInputTokens
            )

            // Store tracked activities
            for activity in parsed.activities {
                let entry = ActivityEntry(
                    activity: activity.description,
                    category: activity.category
                )
                modelContext.insert(entry)
            }

            modelContext.safeSave()

            return SendResult(
                displayText: parsed.displayText,
                calendarActions: parsed.calendarActions,
                alarms: parsed.alarms,
                hasError: false,
                errorMessage: nil
            )
        } catch {
            let errorMsg: String
            let assistantContent: String

            if let aiError = error as? AIError {
                switch aiError {
                case .noAPIKey:
                    errorMsg = "Not connected. Sign in or add an API key in Settings."
                    assistantContent = "I'm not connected yet. Sign in with Apple in Settings to get started, or add your own Anthropic API key."
                case .sessionExpired:
                    errorMsg = "sessionExpired"
                    assistantContent = "Your session has expired. Please sign in again to continue chatting."
                case .rateLimited:
                    errorMsg = "Too many requests — please wait a moment."
                    assistantContent = "I'm getting a lot of requests right now. Give me a moment and try again!"
                case .apiError(let code, let message):
                    errorMsg = "API error (\(code))"
                    if code == 401 {
                        assistantContent = "Your API key appears to be invalid or expired. Please check it in Settings."
                    } else if code == 400 || code == 422 {
                        // 400 = bad request, 422 = validation error (e.g. system prompt too long).
                        // Either way the user can't fix it — keep the message simple.
                        assistantContent = "Something went wrong with the request. Please try again with a shorter message."
                        AppLogger.ai.error("Request rejected (\(code, privacy: .public)): \(message.prefix(300), privacy: .public)")
                    } else if (500...599).contains(code) || code == 502 || code == 503 || code == 529 {
                        // Upstream/backend outage — users don't need to see HTTP codes.
                        assistantContent = "I'm having trouble reaching the server. Please try again in a moment."
                    } else {
                        assistantContent = "Something went wrong. Please try again in a moment."
                        AppLogger.ai.error("Unhandled API error (\(code, privacy: .public)): \(message.prefix(300), privacy: .public)")
                    }
                case .invalidResponse, .parsingError:
                    errorMsg = "Unexpected response from AI."
                    assistantContent = "I received an unexpected response. Please try again."
                case .networkError:
                    errorMsg = "Network error."
                    assistantContent = "I'm having trouble connecting. Please check your internet connection and try again."
                }
            } else {
                errorMsg = "Unexpected error."
                assistantContent = "Something went wrong: \(error.localizedDescription). Please try again."
            }

            AppLogger.ai.error("Chat failed: \(errorMsg, privacy: .public)")
            Breadcrumb.add(category: "ai", message: "Chat error: \(errorMsg)")

            let msg = ChatMessage(
                role: .assistant,
                content: assistantContent,
                conversationID: conversationID
            )
            modelContext.insert(msg)
            modelContext.safeSave()

            return SendResult(
                displayText: assistantContent,
                calendarActions: [],
                alarms: [],
                hasError: true,
                errorMessage: errorMsg
            )
        }
    }

    // MARK: - Calendar Actions

    func executeCalendarActions(_ actions: [CalendarAction]) async -> String? {
        let syncManager = calendarSyncManager
        let enabledLinks = syncManager?.enabledCalendarLinks() ?? []
        let googleCalendarID = enabledLinks.first(where: { $0.calendarSource == .google })?.calendarID
        let appleCalendarID = enabledLinks.first(where: { $0.calendarSource == .apple })?.calendarID
        let useGoogle = googleCalendarID != nil
        var errorMessage: String?

        for action in actions {
            switch action {
            case .create(let title, let start, let end, let description, let recurrence, let dimension):
                // Dedup: check if a task with the same title exists on this day
                let calendar = Calendar.current
                let dayStart = calendar.startOfDay(for: start)
                let dayEnd = calendar.safeDate(byAdding: .day, value: 1, to: dayStart)
                let titleLower = title.lowercased()
                let descriptor = FetchDescriptor<TaskItem>(
                    predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd }
                )
                let existing = (try? modelContext.fetch(descriptor)) ?? []
                let isDuplicate = existing.contains { $0.title.lowercased() == titleLower }
                guard !isDuplicate else { continue }

                // Create calendar event, then local task
                var calendarID: String?

                if let syncManager {
                    do {
                        if useGoogle, let calID = googleCalendarID {
                            let eventID = try await syncManager.googleService.createEvent(
                                calendarID: calID,
                                title: title,
                                startDate: start,
                                endDate: end,
                                description: description
                            )
                            calendarID = "google:\(eventID)"
                        } else if appleCalendarID != nil || syncManager.appleCalendarAuthorized {
                            let eventID = try await syncManager.eventKitService.createEvent(
                                title: title,
                                startDate: start,
                                endDate: end,
                                notes: description,
                                calendarID: appleCalendarID
                            )
                            calendarID = eventID
                        }
                    } catch {
                        errorMessage = "Calendar sync failed, but task was added: \(error.localizedDescription)"
                    }
                }

                let task = TaskItem(
                    title: title,
                    category: .personal,
                    priority: .medium,
                    date: start,
                    icon: calendarID?.hasPrefix("google:") == true ? "\u{1F310}" : "\u{1F4C5}",
                    notes: description ?? "",
                    recurrence: recurrence
                )
                task.externalCalendarID = calendarID
                task.dimension = dimension
                modelContext.insert(task)
                modelContext.safeSave()

            case .delete(let eventID):
                if let syncManager {
                    do {
                        if eventID.hasPrefix("google:") {
                            let googleEventID = String(eventID.dropFirst("google:".count))
                            if let calID = googleCalendarID {
                                try await syncManager.googleService.deleteEvent(
                                    calendarID: calID,
                                    eventID: googleEventID
                                )
                            }
                        } else {
                            try await syncManager.eventKitService.deleteEvent(identifier: eventID)
                        }
                    } catch {
                        errorMessage = "Failed to delete calendar event: \(error.localizedDescription)"
                    }
                }

                let targetID = eventID
                let descriptor = FetchDescriptor<TaskItem>(
                    predicate: #Predicate { $0.externalCalendarID == targetID }
                )
                if let tasks = try? modelContext.fetch(descriptor) {
                    for task in tasks {
                        modelContext.delete(task)
                    }
                    modelContext.safeSave()
                }
            }
        }

        return errorMessage
    }

    // MARK: - Alarm Scheduling

    /// Returns true if the alarm was successfully scheduled.
    @discardableResult
    func scheduleAlarm(_ alarm: ParsedAlarm) async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            return false
        }

        // Try unambiguous formats FIRST. 24-hour and explicit AM/PM both have
        // a single correct interpretation. Only fall through to the ambiguous
        // bare "h:mm" parser if neither matches — and when we do, take the
        // NEXT FUTURE occurrence (so "5:00" requested at 8pm means 5am tomorrow,
        // and "5:00" requested at 6am means 5pm today).
        let calendar = Calendar.current
        let now = Date()
        let trimmed = alarm.timeString.trimmingCharacters(in: .whitespacesAndNewlines)

        var hour: Int?
        var minute: Int?

        // 1. Unambiguous: "HH:mm" or "h:mm a"
        let unambiguousFormats = ["HH:mm", "H:mm", "h:mm a", "h:mma"]
        for format in unambiguousFormats {
            let f = DateFormatter()
            f.dateFormat = format
            f.locale = Locale(identifier: "en_US_POSIX")
            if let d = f.date(from: trimmed) {
                hour = calendar.component(.hour, from: d)
                minute = calendar.component(.minute, from: d)
                break
            }
        }

        // 2. Ambiguous fallback: bare "h:mm" or just "h". Pick the next future
        //    occurrence (today's AM if it's still ahead, today's PM if AM is
        //    past, otherwise tomorrow's AM).
        if hour == nil {
            let f = DateFormatter()
            f.dateFormat = "h:mm"
            f.locale = Locale(identifier: "en_US_POSIX")
            if let d = f.date(from: trimmed) {
                let baseHour = calendar.component(.hour, from: d) // 1-12 mapped to 1-12
                let baseMinute = calendar.component(.minute, from: d)

                // Try AM today, PM today, AM tomorrow — pick the first that's still in the future.
                let candidates: [(hour: Int, dayOffset: Int)] = [
                    (baseHour, 0),         // AM today
                    (baseHour + 12, 0),    // PM today
                    (baseHour, 1),         // AM tomorrow
                ]
                for cand in candidates {
                    var comps = calendar.dateComponents([.year, .month, .day], from: now)
                    if cand.dayOffset > 0 {
                        comps = calendar.dateComponents([.year, .month, .day], from: calendar.safeDate(byAdding: .day, value: cand.dayOffset, to: now))
                    }
                    comps.hour = cand.hour % 24
                    comps.minute = baseMinute
                    if let candidate = calendar.date(from: comps), candidate > now.addingTimeInterval(60) {
                        hour = cand.hour % 24
                        minute = baseMinute
                        var matched = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: candidate)
                        matched.second = 0
                        // Build the final alarmDate via the matched components below by setting hour/minute.
                        // We re-enter the main path so the rest of the function stays a single shape.
                        break
                    }
                }
            }
        }

        guard let hour, let minute else { return false }

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        let alarmDate: Date
        if let candidate = calendar.date(from: components), candidate > now {
            alarmDate = candidate
        } else {
            // Already in the past today — schedule for tomorrow at the same wall-clock time.
            alarmDate = calendar.date(from: components).flatMap {
                calendar.date(byAdding: .day, value: 1, to: $0)
            } ?? now
        }

        let entry = AlarmEntry(
            label: alarm.label,
            time: alarmDate,
            repeatsDaily: alarm.repeatsDaily
        )
        modelContext.insert(entry)

        let notificationManager = NotificationManager()
        notificationManager.scheduleAlarm(
            notificationID: entry.notificationID,
            label: alarm.label,
            time: alarmDate,
            repeatsDaily: alarm.repeatsDaily
        )
        return true
    }

    // MARK: - Response Parsing (shared types + logic)

    enum CalendarAction {
        case create(title: String, start: Date, end: Date, description: String?, recurrence: TaskRecurrence, dimension: LifeDimension?)
        case delete(eventID: String)
    }

    struct ParsedAlarm {
        let timeString: String
        let label: String
        let repeatsDaily: Bool
    }

    private struct ParsedResponse {
        let displayText: String
        let calendarActions: [CalendarAction]
        let activities: [(category: String, description: String)]
        let alarms: [ParsedAlarm]
    }

    /// Build a summary of active habits for the AI volatile context.
    private func buildHabitSummary() -> String {
        var descriptor = FetchDescriptor<HabitItem>(
            predicate: #Predicate { $0.archivedAt == nil }
        )
        descriptor.fetchLimit = 15
        let habits = (try? modelContext.fetch(descriptor)) ?? []
        guard !habits.isEmpty else { return "" }

        let today = Date()
        return habits.map { h in
            let done = h.isCompletedOn(today) ? "done" : "not done"
            let streak = h.currentStreak()
            return "\(h.icon) \(h.title): \(done) today, streak \(streak)"
        }.joined(separator: "\n")
    }

    private func parseResponseTags(from text: String) -> ParsedResponse {
        var displayText = text
        var calendarActions: [CalendarAction] = []
        var activities: [(category: String, description: String)] = []
        var alarms: [ParsedAlarm] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        // Parse CREATE_EVENT tags. Structure: [[CREATE_EVENT:Title|start|end|desc?|recurrence?|dimension?]]
        // Match the outer bracket, then classify each pipe-separated field by content
        // so dropped/reordered optional fields can't silently mis-parse (e.g. "daily"
        // landing in the description slot when the AI omits the description pipe).
        let recurrenceKeywords: Set<String> = ["daily", "weekly", "biweekly", "monthly"]
        let dimensionKeywords: Set<String> = ["physical", "mental", "emotional", "spiritual"]
        let createPattern = /\[\[CREATE_EVENT:([^\]]+?)\]\]/
        for match in text.matches(of: createPattern) {
            let parts = String(match.1).split(separator: "|", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count >= 3 else {
                displayText = displayText.replacingOccurrences(of: String(match.0), with: "")
                continue
            }
            let title = parts[0]
            let startStr = parts[1]
            let endStr = parts[2]

            var desc: String? = nil
            var recurrence: TaskRecurrence = .none
            var dimension: LifeDimension? = nil

            for part in parts.dropFirst(3) where !part.isEmpty {
                let lower = part.lowercased()
                if recurrenceKeywords.contains(lower), recurrence == .none {
                    recurrence = TaskRecurrence(rawValue: lower.capitalized) ?? .none
                } else if dimensionKeywords.contains(lower), dimension == nil {
                    dimension = LifeDimension(rawValue: lower.capitalized)
                } else if desc == nil {
                    desc = part
                }
            }

            if let startDate = dateFormatter.date(from: startStr),
               let endDate = dateFormatter.date(from: endStr) {
                calendarActions.append(.create(
                    title: title,
                    start: startDate,
                    end: endDate,
                    description: desc,
                    recurrence: recurrence,
                    dimension: dimension
                ))
            }
            displayText = displayText.replacingOccurrences(of: String(match.0), with: "")
        }

        // Parse DELETE_EVENT tags
        let deletePattern = /\[\[DELETE_EVENT:(.+?)\]\]/
        for match in text.matches(of: deletePattern) {
            let eventID = String(match.1).trimmingCharacters(in: .whitespaces)
            calendarActions.append(.delete(eventID: eventID))
            displayText = displayText.replacingOccurrences(of: String(match.0), with: "")
        }

        // Parse ACTIVITY tags
        let activityPattern = /\[\[ACTIVITY:(.+?)\|(.+?)\]\]/
        for match in text.matches(of: activityPattern) {
            let category = String(match.1).trimmingCharacters(in: .whitespaces)
            let description = String(match.2).trimmingCharacters(in: .whitespaces)
            activities.append((category: category, description: description))
            displayText = displayText.replacingOccurrences(of: String(match.0), with: "")
        }

        // Parse SET_ALARM tags
        let alarmPattern = /\[\[SET_ALARM:(.+?)\|(.+?)(?:\|(daily))?\]\]/
        for match in text.matches(of: alarmPattern) {
            let timeStr = String(match.1).trimmingCharacters(in: .whitespaces)
            let label = String(match.2).trimmingCharacters(in: .whitespaces)
            let repeats = match.3 != nil
            alarms.append(ParsedAlarm(timeString: timeStr, label: label, repeatsDaily: repeats))
            displayText = displayText.replacingOccurrences(of: String(match.0), with: "")
        }

        return ParsedResponse(
            displayText: displayText.trimmingCharacters(in: .whitespacesAndNewlines),
            calendarActions: calendarActions,
            activities: activities,
            alarms: alarms
        )
    }
}
