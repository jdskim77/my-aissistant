import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct NextCheckInEntry: TimelineEntry {
    let date: Date
    let timeSlot: String
    let greeting: String
    let minutesUntil: Int
}

// MARK: - Timeline Provider

struct NextCheckInProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextCheckInEntry {
        NextCheckInEntry(date: Date(), timeSlot: "Afternoon", greeting: "How's your day going?", minutesUntil: 45)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NextCheckInEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NextCheckInEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let currentMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

        let windows = enabledWindows()
        let (slot, greeting, nextHour, nextMinute) = nextCheckIn(currentMinutes: currentMinutes, windows: windows)

        // Build target date using both hour and minute
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = nextHour
        components.minute = nextMinute
        var nextDate = calendar.date(from: components) ?? now
        if nextDate <= now {
            nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate) ?? now
        }
        let minutes = max(0, Int(nextDate.timeIntervalSince(now) / 60))

        let entry = NextCheckInEntry(date: now, timeSlot: slot, greeting: greeting, minutesUntil: minutes)
        let refreshDate = calendar.safeDate(byAdding: .minute, value: 15, to: now)
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }

    /// Read enabled windows from App Group UserDefaults (written by main app).
    /// Falls back to hardcoded defaults if no data is available.
    private func enabledWindows() -> [WidgetCheckInWindow] {
        let defaults = UserDefaults(suiteName: "group.com.myaissistant.shared")

        if let data = defaults?.data(forKey: "enabledCheckInWindows"),
           let decoded = try? JSONDecoder().decode([WidgetCheckInWindow].self, from: data) {
            return decoded
        }

        // Fallback to hardcoded defaults
        return [
            WidgetCheckInWindow(name: "Morning", hour: 8, minute: 0, greeting: "Good morning!"),
            WidgetCheckInWindow(name: "Midday", hour: 13, minute: 0, greeting: "How's your morning going?"),
            WidgetCheckInWindow(name: "Afternoon", hour: 18, minute: 0, greeting: "Afternoon check-in"),
            WidgetCheckInWindow(name: "Night", hour: 22, minute: 0, greeting: "Evening reflection"),
        ]
    }

    private func nextCheckIn(
        currentMinutes: Int,
        windows: [WidgetCheckInWindow]
    ) -> (slot: String, greeting: String, nextHour: Int, nextMinute: Int) {
        let sorted = windows.sorted { $0.hour * 60 + $0.minute < $1.hour * 60 + $1.minute }

        // Find next window that hasn't passed yet
        for window in sorted {
            let windowMinutes = window.hour * 60 + window.minute
            if currentMinutes < windowMinutes {
                return (window.name, window.greeting, window.hour, window.minute)
            }
        }

        // All passed — wrap to first window tomorrow
        if let first = sorted.first {
            return (first.name, first.greeting, first.hour, first.minute)
        }

        return ("Morning", "Good morning!", 8, 0)
    }
}

// MARK: - Widget Data Model

struct WidgetCheckInWindow: Codable {
    let name: String
    let hour: Int
    let minute: Int
    let greeting: String
}

// MARK: - Widget View

struct NextCheckInWidgetView: View {
    let entry: NextCheckInEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "clock.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.orange)
                Text("Next Check-in")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(entry.timeSlot)
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundColor(.primary)

            Text(entry.greeting)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(2)

            Spacer()

            if entry.minutesUntil > 0 {
                Text("in \(entry.minutesUntil) min")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.orange)
            } else {
                Text("Now")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.green)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget Configuration

struct NextCheckInWidget: Widget {
    let kind = "NextCheckInWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextCheckInProvider()) { entry in
            NextCheckInWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Check-in")
        .description("Shows your next check-in time.")
        .supportedFamilies([.systemSmall])
    }
}
