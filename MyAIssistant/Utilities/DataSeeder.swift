import Foundation
import SwiftData

struct DataSeeder {
    static func seedIfEmpty(context: ModelContext) {
        #if !DEBUG
        // Only seed sample data in debug builds — real users start with a clean slate
        return
        #else
        let descriptor = FetchDescriptor<TaskItem>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        // Seed sample tasks centered around February 2026 Dubai trip
        let tasks = [
            // Completed
            TaskItem(title: "Book flights", category: .travel, priority: .high, date: Date.from(month: 2, day: 3), done: true, icon: "✈️", notes: "LAX to DXB, Emirates"),
            TaskItem(title: "Renew passport", category: .errand, priority: .high, date: Date.from(month: 2, day: 5), done: true, icon: "📘", notes: "Expedited processing"),
            TaskItem(title: "Book hotel", category: .travel, priority: .high, date: Date.from(month: 2, day: 6), done: true, icon: "🏨", notes: "Atlantis The Palm, 5 nights"),

            // Today-ish
            TaskItem(title: "Book airport transfer", category: .travel, priority: .high, date: Date.from(month: 2, day: 16), icon: "🚐", notes: "Private car to LAX"),
            TaskItem(title: "Pick up travel insurance", category: .errand, priority: .high, date: Date.from(month: 2, day: 16), icon: "📋", notes: "Coverage for Feb 15-20"),

            // Upcoming
            TaskItem(title: "Exchange currency", category: .errand, priority: .high, date: Date.from(month: 2, day: 17), icon: "💱", notes: "USD to AED, ~2000"),
            TaskItem(title: "Pack luggage", category: .travel, priority: .high, date: Date.from(month: 2, day: 18), icon: "🧳", notes: "Check weather forecast first"),
            TaskItem(title: "Depart for Dubai", category: .travel, priority: .high, date: Date.from(month: 2, day: 19), icon: "🛫", notes: "Flight EK 216, 4:25 PM"),
            TaskItem(title: "Desert safari", category: .travel, priority: .medium, date: Date.from(month: 2, day: 21), icon: "🏜️", notes: "Evening tour with dinner"),
            TaskItem(title: "Return flight", category: .travel, priority: .high, date: Date.from(month: 2, day: 24), icon: "🛬", notes: "Flight EK 215, 2:10 AM"),
            TaskItem(title: "Grocery run", category: .errand, priority: .medium, date: Date.from(month: 2, day: 25), icon: "🛒", notes: "Restock after trip"),
            TaskItem(title: "Pay bills", category: .errand, priority: .high, date: Date.from(month: 2, day: 27), icon: "💳", notes: "Rent + utilities"),
            TaskItem(title: "Car service", category: .errand, priority: .medium, date: Date.from(month: 3, day: 1), icon: "🔧", notes: "Oil change + inspection"),
        ]

        for task in tasks {
            context.insert(task)
        }

        // Seed some check-in records for pattern display
        let calendar = Calendar.current
        for dayOffset in 1...6 {
            let date = calendar.safeDate(byAdding: .day, value: -dayOffset, to: Date())
            let record = CheckInRecord(
                timeSlot: .morning,
                date: date,
                completed: dayOffset != 3  // skip one day for variety
            )
            context.insert(record)
        }

        try? context.save()
        #endif
    }
}
