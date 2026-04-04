import EventKit
import Foundation
import SwiftData
import SwiftUI

/// Orchestrates calendar sync: request access, list calendars, import/export events.
@MainActor
final class CalendarSyncManager: ObservableObject {
    private let modelContext: ModelContext
    let eventKitService = EventKitService()
    let googleService: GoogleCalendarService

    @Published var appleCalendars: [EKCalendar] = []
    @Published var googleCalendars: [GoogleCalendar] = []
    @Published var isSyncing = false
    @Published var lastError: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        // Use stored client ID if user set one, otherwise fall back to bundled default
        let storedID = (UserDefaults.standard.string(forKey: AppConstants.googleClientIDKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clientID = storedID.isEmpty ? AppConstants.googleClientID : storedID
        print("[CalendarSyncManager] Using Google client ID: \(clientID.prefix(30))...")
        self.googleService = GoogleCalendarService(clientID: clientID)
    }

    func setGoogleClientID(_ clientID: String) {
        UserDefaults.standard.set(clientID, forKey: AppConstants.googleClientIDKey)
        Task { await googleService.updateClientID(clientID) }
    }

    // MARK: - Apple Calendar Access

    var appleCalendarAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAppleCalendarAccess() async -> Bool {
        let granted = await eventKitService.requestAccess()
        if granted {
            await loadAppleCalendars()
        }
        return granted
    }

    func loadAppleCalendars() async {
        appleCalendars = await eventKitService.availableCalendars()
    }

    // MARK: - Reminders Access

    @Published var reminderLists: [EKCalendar] = []

    var remindersAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    func requestRemindersAccess() async -> Bool {
        let granted = await eventKitService.requestReminderAccess()
        if granted {
            await loadReminderLists()
        }
        return granted
    }

    func loadReminderLists() async {
        reminderLists = await eventKitService.availableReminderLists()
    }

    // MARK: - Google Calendar Access

    func googleCalendarConnected() async -> Bool {
        await googleService.isAuthenticated
    }

    func loadGoogleCalendars() async {
        do {
            googleCalendars = try await googleService.fetchCalendars()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Linked Calendars

    func linkedCalendars() -> [CalendarLink] {
        let descriptor = FetchDescriptor<CalendarLink>(
            sortBy: [SortDescriptor(\CalendarLink.name)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func enabledCalendarLinks() -> [CalendarLink] {
        let descriptor = FetchDescriptor<CalendarLink>(
            predicate: #Predicate { $0.enabled == true },
            sortBy: [SortDescriptor(\CalendarLink.name)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func linkCalendar(source: CalendarSource, calendarID: String, name: String, color: String) {
        // Check if already linked
        let existingLinks = linkedCalendars()
        if existingLinks.contains(where: { $0.calendarID == calendarID && $0.source == source.rawValue }) {
            return
        }

        let link = CalendarLink(
            source: source,
            calendarID: calendarID,
            name: name,
            color: color
        )
        modelContext.insert(link)
        modelContext.safeSave()
    }

    func unlinkCalendar(_ link: CalendarLink) {
        modelContext.delete(link)
        modelContext.safeSave()
    }

    func toggleCalendarLink(_ link: CalendarLink) {
        link.enabled.toggle()
        modelContext.safeSave()
    }

    // MARK: - Deduplication

    /// Check if a task with an equivalent title already exists on the same day.
    /// Uses normalized comparison to catch birthday variants
    /// (e.g. "John's Birthday" matches "John").
    private func taskExistsOnSameDay(title: String, date: Date) -> Bool {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.safeDate(byAdding: .day, value: 1, to: dayStart)
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let newKey = Self.deduplicationKey(for: title)
        return existing.contains { Self.deduplicationKey(for: $0.title) == newKey }
    }

    /// Normalize a title for dedup: lowercase, strip birthday suffixes/prefixes, trim.
    private static func deduplicationKey(for title: String) -> String {
        var key = title.lowercased()
        for suffix in ["'s birthday", "\u{2019}s birthday", " birthday", "'s bday"] {
            if key.hasSuffix(suffix) {
                key = String(key.dropLast(suffix.count))
            }
        }
        for prefix in ["birthday - ", "birthday: "] {
            if key.hasPrefix(prefix) {
                key = String(key.dropFirst(prefix.count))
            }
        }
        return key.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Sync Apple Calendar Events

    func syncAppleCalendar(days: Int = 30) async {
        guard appleCalendarAuthorized else { return }

        isSyncing = true
        defer { isSyncing = false }

        let enabledLinks = enabledCalendarLinks().filter { $0.calendarSource == .apple }
        guard !enabledLinks.isEmpty else { return }

        let calendarIDs = enabledLinks.map(\.calendarID)
        let startDate = Calendar.current.startOfDay(for: Date())
        let endDate = Calendar.current.safeDate(byAdding: .day, value: days, to: startDate)

        let events = await eventKitService.events(in: calendarIDs, from: startDate, to: endDate)

        for ekEvent in events {
            let eventID = ekEvent.eventIdentifier ?? ""
            guard !eventID.isEmpty else { continue }

            // Check if task already exists for this calendar event
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.externalCalendarID == eventID }
            )
            let existing = (try? modelContext.fetch(descriptor)) ?? []

            if let existingTask = existing.first {
                // Update existing task
                existingTask.title = ekEvent.title ?? "Untitled"
                existingTask.date = ekEvent.startDate
                existingTask.notes = ekEvent.notes ?? ""
            } else {
                // Skip if a task with the same title already exists on this day (cross-source dedup)
                let title = ekEvent.title ?? "Untitled"
                guard !taskExistsOnSameDay(title: title, date: ekEvent.startDate) else { continue }

                let task = TaskItem(
                    title: title,
                    category: .personal,
                    priority: .medium,
                    date: ekEvent.startDate,
                    icon: "📅",
                    notes: ekEvent.notes ?? ""
                )
                task.externalCalendarID = eventID
                modelContext.insert(task)
            }
        }

        // Update last synced timestamps
        for link in enabledLinks {
            link.lastSynced = Date()
        }

        modelContext.safeSave()
    }

    // MARK: - Sync Google Calendar Events

    func syncGoogleCalendar(days: Int = 30) async {
        guard await googleCalendarConnected() else { return }

        isSyncing = true
        defer { isSyncing = false }

        let enabledLinks = enabledCalendarLinks().filter { $0.calendarSource == .google }
        guard !enabledLinks.isEmpty else { return }

        let startDate = Calendar.current.startOfDay(for: Date())
        let endDate = Calendar.current.safeDate(byAdding: .day, value: days, to: startDate)

        for link in enabledLinks {
            do {
                let events = try await googleService.fetchEvents(
                    calendarID: link.calendarID,
                    from: startDate,
                    to: endDate
                )

                for event in events {
                    let googleID = "google:\(event.id)"
                    guard let startDate = event.startDate else { continue }

                    let descriptor = FetchDescriptor<TaskItem>(
                        predicate: #Predicate { $0.externalCalendarID == googleID }
                    )
                    let existing = (try? modelContext.fetch(descriptor)) ?? []

                    if let existingTask = existing.first {
                        existingTask.title = event.title
                        existingTask.date = startDate
                        existingTask.notes = event.description ?? ""
                    } else {
                        // Skip if a task with the same title already exists on this day (cross-source dedup)
                        guard !taskExistsOnSameDay(title: event.title, date: startDate) else { continue }

                        let task = TaskItem(
                            title: event.title,
                            category: .personal,
                            priority: .medium,
                            date: startDate,
                            icon: "🌐",
                            notes: event.description ?? ""
                        )
                        task.externalCalendarID = googleID
                        modelContext.insert(task)
                    }
                }

                link.lastSynced = Date()
            } catch {
                lastError = error.localizedDescription
            }
        }

        modelContext.safeSave()
    }

    // MARK: - Full Sync

    /// Re-entrancy guard — prevents concurrent syncs from racing.
    private var isSyncingAll = false

    func syncAll() async {
        guard !isSyncingAll else { return }
        isSyncingAll = true
        isSyncing = true
        defer {
            isSyncing = false
            isSyncingAll = false
        }

        await syncAppleCalendar()
        await syncGoogleCalendar()
        await syncReminders()
    }

    // MARK: - Sync Reminders

    func syncReminders() async {
        guard remindersAuthorized else { return }

        // Don't set isSyncing here if syncAll already set it (prevents flicker)
        let ownsSyncing = !isSyncingAll
        if ownsSyncing { isSyncing = true }
        defer { if ownsSyncing { isSyncing = false } }

        let enabledLinks = enabledCalendarLinks().filter { $0.calendarSource == .reminders }
        guard !enabledLinks.isEmpty else { return }

        let listIDs = enabledLinks.map(\.calendarID)

        // Fetch BOTH incomplete and recently completed reminders
        let incompleteReminders = await eventKitService.incompleteReminders(in: listIDs)
        let lastSync = enabledLinks.compactMap(\.lastSynced).min() ?? Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let completedReminders = await eventKitService.completedReminders(in: listIDs, since: lastSync)

        let allReminders = incompleteReminders + completedReminders

        // Track which reminder IDs we've seen — for orphan detection
        var seenReminderIDs: Set<String> = []

        for reminder in allReminders {
            let reminderID = "reminder:\(reminder.calendarItemIdentifier)"
            seenReminderIDs.insert(reminderID)

            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.externalCalendarID == reminderID }
            )
            let existing = (try? modelContext.fetch(descriptor)) ?? []

            if let existingTask = existing.first {
                // Update existing task from reminder
                existingTask.title = reminder.title ?? "Untitled"
                if let dueDate = reminder.dueDateComponents?.date {
                    existingTask.date = dueDate
                }
                existingTask.notes = reminder.notes ?? ""
                // Sync completion: Reminders → app
                if reminder.isCompleted && !existingTask.done {
                    existingTask.done = true
                    existingTask.completedAt = reminder.completionDate ?? Date()
                } else if !reminder.isCompleted && existingTask.done {
                    existingTask.done = false
                    existingTask.completedAt = nil
                }
            } else if !reminder.isCompleted {
                // New incomplete reminder — import as task
                let title = reminder.title ?? "Untitled"
                let dueDate = reminder.dueDateComponents?.date ?? reminder.creationDate ?? Date()
                guard !taskExistsOnSameDay(title: title, date: dueDate) else { continue }

                let priority: TaskPriority = {
                    switch reminder.priority {
                    case 1...4: return .high
                    case 5: return .medium
                    case 6...9: return .low
                    default: return .medium
                    }
                }()

                let task = TaskItem(
                    title: title,
                    category: .personal,
                    priority: priority,
                    date: dueDate,
                    icon: "☑️",
                    notes: reminder.notes ?? ""
                )
                task.externalCalendarID = reminderID
                modelContext.insert(task)
            }
        }

        // Clean up orphaned tasks (reminder was deleted in Reminders app)
        await cleanUpOrphanedReminderTasks(seenIDs: seenReminderIDs, listIDs: listIDs)

        for link in enabledLinks {
            link.lastSynced = Date()
        }
        modelContext.safeSave()
    }

    /// Remove tasks whose linked reminder no longer exists.
    private func cleanUpOrphanedReminderTasks(seenIDs: Set<String>, listIDs: [String]) async {
        // Fetch all tasks linked to reminders
        let descriptor = FetchDescriptor<TaskItem>()
        let allTasks = (try? modelContext.fetch(descriptor)) ?? []

        for task in allTasks {
            guard let extID = task.externalCalendarID, extID.hasPrefix("reminder:") else { continue }
            // If this reminder ID wasn't in the fetch results, it's been deleted
            if !seenIDs.contains(extID) {
                modelContext.delete(task)
            }
        }
    }

    /// Immediately sync a single task's completion state to Reminders.
    /// Called from TaskManager.toggleCompletion() for reminder-linked tasks.
    func syncTaskCompletionToReminders(_ task: TaskItem) async {
        guard let extID = task.externalCalendarID, extID.hasPrefix("reminder:") else { return }
        let reminderID = String(extID.dropFirst("reminder:".count))
        if task.done {
            try? await eventKitService.completeReminder(identifier: reminderID)
        } else {
            try? await eventKitService.uncompleteReminder(identifier: reminderID)
        }
    }

    // MARK: - Push to Apple Calendar

    func pushTaskToAppleCalendar(_ task: TaskItem, calendarID: String? = nil) async throws -> String {
        let endDate = Calendar.current.date(byAdding: .hour, value: 1, to: task.date) ?? task.date
        let eventID = try await eventKitService.createEvent(
            title: task.title,
            startDate: task.date,
            endDate: endDate,
            notes: task.notes,
            calendarID: calendarID
        )
        task.externalCalendarID = eventID
        modelContext.safeSave()
        return eventID
    }

    func updateCalendarEvent(for task: TaskItem) async {
        guard let eventID = task.externalCalendarID, !eventID.hasPrefix("google:") else { return }
        let endDate = Calendar.current.date(byAdding: .hour, value: 1, to: task.date) ?? task.date
        try? await eventKitService.updateEvent(
            identifier: eventID,
            title: task.title,
            startDate: task.date,
            endDate: endDate,
            notes: task.notes
        )
    }

    func deleteCalendarEvent(for task: TaskItem) async {
        guard let eventID = task.externalCalendarID else { return }

        if eventID.hasPrefix("google:") {
            let googleEventID = String(eventID.dropFirst("google:".count))
            let googleLinks = enabledCalendarLinks().filter { $0.calendarSource == .google }
            if let calendarID = googleLinks.first?.calendarID {
                try? await googleService.deleteEvent(calendarID: calendarID, eventID: googleEventID)
            }
        } else if eventID.hasPrefix("reminder:") {
            // Mark reminder as complete in Reminders app (don't actually delete it)
            let reminderID = String(eventID.dropFirst("reminder:".count))
            try? await eventKitService.completeReminder(identifier: reminderID)
        } else {
            // Delete from Apple Calendar
            try? await eventKitService.deleteEvent(identifier: eventID)
        }
    }

    // MARK: - Push to Google Calendar

    func pushTaskToGoogleCalendar(_ task: TaskItem, calendarID: String? = nil) async throws -> String {
        let googleLinks = enabledCalendarLinks().filter { $0.calendarSource == .google }
        guard let targetCalendarID = calendarID ?? googleLinks.first?.calendarID else {
            throw GoogleCalendarError.notAuthenticated
        }

        let endDate = Calendar.current.date(byAdding: .hour, value: 1, to: task.date) ?? task.date
        let eventID = try await googleService.createEvent(
            calendarID: targetCalendarID,
            title: task.title,
            startDate: task.date,
            endDate: endDate,
            description: task.notes.isEmpty ? nil : task.notes
        )
        task.externalCalendarID = "google:\(eventID)"
        modelContext.safeSave()
        return eventID
    }

    func updateGoogleCalendarEvent(for task: TaskItem) async {
        guard let eventID = task.externalCalendarID, eventID.hasPrefix("google:") else { return }
        let googleEventID = String(eventID.dropFirst("google:".count))
        let googleLinks = enabledCalendarLinks().filter { $0.calendarSource == .google }
        guard let calendarID = googleLinks.first?.calendarID else { return }

        let endDate = Calendar.current.date(byAdding: .hour, value: 1, to: task.date) ?? task.date
        try? await googleService.updateEvent(
            calendarID: calendarID,
            eventID: googleEventID,
            title: task.title,
            startDate: task.date,
            endDate: endDate,
            description: task.notes.isEmpty ? nil : task.notes
        )
    }

    // MARK: - Listen for External Changes

    func startListeningForChanges() {
        Task {
            for await _ in await eventKitService.storeChanges() {
                // EKEventStoreChanged fires for both calendar and reminder changes
                await syncAppleCalendar()
                await syncReminders()
                // Refresh Watch and widgets after external changes
                await MainActor.run {
                    NotificationCenter.default.post(name: .watchRequestedUpdate, object: nil)
                }
            }
        }
    }
}
