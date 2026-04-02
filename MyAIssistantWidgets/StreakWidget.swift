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
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<StreakEntry>) -> Void) {
        let entry = loadEntry()
        let refreshDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }

    private func loadEntry() -> StreakEntry {
        if let data = WidgetData.load() {
            return StreakEntry(date: Date(), streakDays: data.streakDays, isActive: data.streakActive)
        }
        return StreakEntry(date: Date(), streakDays: 0, isActive: false)
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
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
        #else
        .supportedFamilies([.systemSmall])
        #endif
    }
}
