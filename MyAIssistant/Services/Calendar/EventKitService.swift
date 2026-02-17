import EventKit
import Foundation

/// Wraps EKEventStore for Apple Calendar read/write operations.
actor EventKitService {
    private let store = EKEventStore()

    // MARK: - Authorization

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

    // MARK: - Calendars

    func availableCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
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
