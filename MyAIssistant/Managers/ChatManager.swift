import Foundation
import SwiftData
import SwiftUI
import UserNotifications

// MARK: - ChatManager

@MainActor
final class ChatManager: ObservableObject {
    private let modelContext: ModelContext

    // Dependencies injected after init (set by the app entry point or view)
    var taskManager: TaskManager?
    var patternEngine: PatternEngine?
    var keychainService: KeychainService = KeychainService()
    var calendarSyncManager: CalendarSyncManager?
    var usageGateManager: UsageGateManager?
    var subscriptionTier: SubscriptionTier = .free

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

            let systemPrompt = AIPromptBuilder.chatSystemPrompt(
                scheduleSummary: taskManager?.scheduleSummary() ?? "",
                completionRate: patternEngine?.completionRate() ?? 0,
                streak: patternEngine?.currentStreak() ?? 0,
                hasGoogleCalendar: hasGoogle,
                hasAppleCalendar: hasApple,
                activitySummary: patternEngine?.activitySummaryText() ?? "",
                patternInsights: patternEngine?.patternInsightsText() ?? ""
            )

            let aiResponse = try await provider.sendMessage(
                userMessage: text,
                conversationHistory: Array(priorHistory.suffix(10)),
                systemPrompt: systemPrompt
            )

            let parsed = parseResponseTags(from: aiResponse.content)

            let assistantMessage = ChatMessage(
                role: .assistant,
                content: parsed.displayText,
                conversationID: conversationID
            )
            modelContext.insert(assistantMessage)

            // Track usage
            usageGateManager?.recordChatMessage(
                inputTokens: aiResponse.inputTokens,
                outputTokens: aiResponse.outputTokens
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

            if let aiError = error as? AIError, case .noAPIKey = aiError {
                errorMsg = "No API key set. Add one in Settings."
                assistantContent = "I need an API key to work. Please add your Anthropic API key in Settings to get started!"
            } else if let aiError = error as? AIError, case .rateLimited = aiError {
                errorMsg = "Too many requests — please wait a moment."
                assistantContent = "I'm getting a lot of requests right now. Give me a moment and try again!"
            } else {
                errorMsg = "Connection issue — please try again."
                assistantContent = "I'm having trouble connecting right now. Please check your internet connection and try again."
            }

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
            case .create(let title, let start, let end, let description, let recurrence):
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

        let formats = ["HH:mm", "H:mm", "h:mm a", "h:mma", "h:mm"]
        var parsedTime: Date?
        for format in formats {
            let f = DateFormatter()
            f.dateFormat = format
            f.locale = Locale(identifier: "en_US_POSIX")
            if let d = f.date(from: alarm.timeString) { parsedTime = d; break }
        }
        guard let parsedTime else { return false }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: parsedTime)
        let minute = calendar.component(.minute, from: parsedTime)

        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        let alarmDate: Date
        if let candidate = calendar.date(from: components), candidate > now {
            alarmDate = candidate
        } else {
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
        case create(title: String, start: Date, end: Date, description: String?, recurrence: TaskRecurrence)
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

    private func parseResponseTags(from text: String) -> ParsedResponse {
        var displayText = text
        var calendarActions: [CalendarAction] = []
        var activities: [(category: String, description: String)] = []
        var alarms: [ParsedAlarm] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        // Parse CREATE_EVENT tags
        let createPattern = /\[\[CREATE_EVENT:(.+?)\|(.+?)\|(.+?)\|(.*?)(?:\|(daily|weekly|biweekly|monthly))?\]\]/
        for match in text.matches(of: createPattern) {
            let title = String(match.1).trimmingCharacters(in: .whitespaces)
            let startStr = String(match.2).trimmingCharacters(in: .whitespaces)
            let endStr = String(match.3).trimmingCharacters(in: .whitespaces)
            let desc = String(match.4).trimmingCharacters(in: .whitespaces)
            let recStr = match.5.map { String($0).lowercased() }
            let recurrence = recStr.flatMap { TaskRecurrence(rawValue: $0.capitalized) } ?? .none

            if let startDate = dateFormatter.date(from: startStr),
               let endDate = dateFormatter.date(from: endStr) {
                calendarActions.append(.create(
                    title: title,
                    start: startDate,
                    end: endDate,
                    description: desc.isEmpty ? nil : desc,
                    recurrence: recurrence
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
