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
        let hour = calendar.component(.hour, from: now)

        let (slot, greeting, nextHour) = nextCheckIn(hour: hour)
        var nextDate = calendar.date(bySetting: .hour, value: nextHour, of: now) ?? now
        if nextDate <= now {
            nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate) ?? now
        }
        let minutes = max(0, Int(nextDate.timeIntervalSince(now) / 60))

        let entry = NextCheckInEntry(date: now, timeSlot: slot, greeting: greeting, minutesUntil: minutes)
        let refreshDate = calendar.date(byAdding: .minute, value: 15, to: now)!
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }

    private func nextCheckIn(hour: Int) -> (slot: String, greeting: String, nextHour: Int) {
        if hour < 8 { return ("Morning", "Good morning!", 8) }
        if hour < 13 { return ("Midday", "How's your morning going?", 13) }
        if hour < 18 { return ("Afternoon", "Afternoon check-in", 18) }
        if hour < 22 { return ("Night", "Evening reflection", 22) }
        return ("Morning", "Good morning!", 8) // Tomorrow
    }
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
