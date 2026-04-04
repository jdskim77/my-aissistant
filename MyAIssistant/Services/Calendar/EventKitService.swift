import EventKit
import Foundation

/// Wraps EKEventStore for Apple Calendar read/write operations.
actor EventKitService {
    private let store = EKEventStore()

    // MARK: - Authorization (Events)

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                return try await store.requestFullAccessToEvents()
            } else {
                return try await store.requestAccess(to: .event)
            }
        } catch {
            return false
        }
    }

    // MARK: - Authorization (Reminders)

    var reminderAuthorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    func requestReminderAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                return try await store.requestFullAccessToReminders()
            } else {
                return try await store.requestAccess(to: .reminder)
            }
        } catch {
            return false
        }
    }

    // MARK: - Calendars (Events)

    func availableCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
    }

    // MARK: - Reminder Lists

    func availableReminderLists() -> [EKCalendar] {
        store.calendars(for: .reminder)
    }

    // MARK: - Fetch Reminders

    /// Fetches incomplete reminders from the specified lists.
    func incompleteReminders(in listIDs: [String]) async -> [EKReminder] {
        let lists = listIDs.compactMap { store.calendar(withIdentifier: $0) }
        guard !lists.isEmpty else { return [] }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: lists
        )

        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    /// Fetches reminders that were completed recently (for sync tracking).
    func completedReminders(in listIDs: [String], since date: Date) async -> [EKReminder] {
        let lists = listIDs.compactMap { store.calendar(withIdentifier: $0) }
        guard !lists.isEmpty else { return [] }

        let predicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: date,
            ending: Date(),
            calendars: lists
        )

        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    /// Mark a reminder as complete in the Reminders app.
    func completeReminder(identifier: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        reminder.isCompleted = true
        reminder.completionDate = Date()
        try store.save(reminder, commit: true)
    }

    /// Mark a reminder as incomplete in the Reminders app.
    func uncompleteReminder(identifier: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        reminder.isCompleted = false
        reminder.completionDate = nil
        try store.save(reminder, commit: true)
    }

    func calendar(withIdentifier id: String) -> EKCalendar? {
        store.calendar(withIdentifier: id)
    }

    // MARK: - Fetch Events

    func events(
        in calendarIDs: [String],
        from startDate: Date,
        to endDate: Date
    ) -> [EKEvent] {
        let calendars = calendarIDs.compactMap { store.calendar(withIdentifier: $0) }
        guard !calendars.isEmpty else { return [] }

        let predicate = store.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: calendars
        )
        return store.events(matching: predicate)
    }

    func event(withIdentifier id: String) -> EKEvent? {
        store.event(withIdentifier: id)
    }

    // MARK: - Create / Update / Delete

    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String?,
        calendarID: String?
    ) throws -> String {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes

        if let calendarID, let cal = store.calendar(withIdentifier: calendarID) {
            event.calendar = cal
        } else {
            event.calendar = store.defaultCalendarForNewEvents
        }

        try store.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    func updateEvent(
        identifier: String,
        title: String?,
        startDate: Date?,
        endDate: Date?,
        notes: String?
    ) throws {
        guard let event = store.event(withIdentifier: identifier) else { return }

        if let title { event.title = title }
        if let startDate { event.startDate = startDate }
        if let endDate { event.endDate = endDate }
        if let notes { event.notes = notes }

        try store.save(event, span: .thisEvent)
    }

    func deleteEvent(identifier: String) throws {
        guard let event = store.event(withIdentifier: identifier) else { return }
        try store.remove(event, span: .thisEvent)
    }

    // MARK: - Change Observation

    /// Returns an AsyncStream that emits whenever the event store changes externally.
    func storeChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let observer = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged,
                object: store,
                queue: .main
            ) { _ in
                continuation.yield()
            }
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
