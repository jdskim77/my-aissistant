import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct StreakEntry: TimelineEntry {
    let date: Date
    let streakDays: Int
    let isActive: Bool
}

// MARK: - Timeline Provider

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), streakDays: 5, isActive: true)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (StreakEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<StreakEntry>) -> Void) {
        // In production, read from shared App Group SwiftData container
        let entry = StreakEntry(date: Date(), streakDays: 0, isActive: false)
        let refreshDate = Calendar.current.safeDate(byAdding: .hour, value: 1, to: Date())
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }
}

// MARK: - Widget View

struct StreakWidgetView: View {
    let entry: StreakEntry

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 28))
                .foregroundColor(entry.isActive ? .orange : .gray)

            Text("\(entry.streakDays)")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundColor(.primary)

            Text(entry.streakDays == 1 ? "day" : "days")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            if entry.isActive {
                Text("Keep it up!")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            } else {
                Text("Complete a task!")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget Configuration

struct StreakWidget: Widget {
    let kind = "StreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Streak")
        .description("Track your completion streak.")
        .supportedFamilies([.systemSmall])
    }
}
