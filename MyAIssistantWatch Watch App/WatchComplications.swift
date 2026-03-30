#if os(watchOS)
import WidgetKit
import SwiftUI

// MARK: - Next Event Complication

struct NextEventEntry: TimelineEntry {
    let date: Date
    let taskTitle: String
    let taskTime: String?
    let remainingCount: Int
}

struct NextEventProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextEventEntry {
        NextEventEntry(date: Date(), taskTitle: "Team Standup", taskTime: "10:30 AM", remainingCount: 5)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextEventEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextEventEntry>) -> Void) {
        let data = loadScheduleData()
        let now = Date()
        let upNext = data?.tasks.first(where: { !$0.done && $0.date >= now })
            ?? data?.tasks.first(where: { !$0.done })

        let entry = NextEventEntry(
            date: now,
            taskTitle: upNext?.title ?? "No tasks",
            taskTime: upNext?.hasTime == true ? upNext?.timeString : nil,
            remainingCount: data?.tasks.filter { !$0.done }.count ?? 0
        )

        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func loadScheduleData() -> WatchScheduleData? {
        guard let data = UserDefaults.standard.data(forKey: "watchScheduleCache") else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WatchScheduleData.self, from: data)
    }
}

struct NextEventComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: NextEventEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangularView
        case .accessoryCircular:
            circularView
        case .accessoryCorner:
            cornerView
        case .accessoryInline:
            inlineView
        default:
            rectangularView
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 10))
                Text("UP NEXT")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.accentColor)

            Text(entry.taskTitle)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)

            if let time = entry.taskTime {
                Text(time)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text("\(entry.remainingCount) remaining")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var circularView: some View {
        VStack(spacing: 2) {
            Image(systemName: "checklist")
                .font(.system(size: 14))
            Text("\(entry.remainingCount)")
                .font(.system(size: 16, weight: .bold))
        }
    }

    private var cornerView: some View {
        Text("\(entry.remainingCount)")
            .font(.system(size: 20, weight: .bold))
            .widgetLabel {
                Text("tasks left")
            }
    }

    private var inlineView: some View {
        Text("\(entry.remainingCount) tasks • \(entry.taskTitle)")
    }
}

struct NextEventComplication: Widget {
    let kind = "NextEventComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextEventProvider()) { entry in
            NextEventComplicationView(entry: entry)
        }
        .configurationDisplayName("Up Next")
        .description("Shows your next task or event.")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}

// MARK: - Streak Complication

struct StreakComplicationEntry: TimelineEntry {
    let date: Date
    let streakDays: Int
    let isActive: Bool
}

struct StreakComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakComplicationEntry {
        StreakComplicationEntry(date: Date(), streakDays: 5, isActive: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakComplicationEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakComplicationEntry>) -> Void) {
        let data = loadScheduleData()
        let entry = StreakComplicationEntry(
            date: Date(),
            streakDays: data?.streakDays ?? 0,
            isActive: (data?.streakDays ?? 0) > 0
        )
        let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func loadScheduleData() -> WatchScheduleData? {
        guard let data = UserDefaults.standard.data(forKey: "watchScheduleCache") else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WatchScheduleData.self, from: data)
    }
}

struct StreakComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: StreakComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 1) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14))
                    .foregroundColor(entry.isActive ? .orange : .gray)
                Text("\(entry.streakDays)")
                    .font(.system(size: 16, weight: .bold))
            }
        case .accessoryCorner:
            Text("\(entry.streakDays)")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(entry.isActive ? .orange : .gray)
                .widgetLabel {
                    Text("day streak")
                }
        case .accessoryInline:
            Label("\(entry.streakDays)-day streak", systemImage: "flame.fill")
        default:
            VStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(entry.isActive ? .orange : .gray)
                Text("\(entry.streakDays)d")
                    .font(.system(size: 14, weight: .bold))
            }
        }
    }
}

struct StreakComplication: Widget {
    let kind = "StreakComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakComplicationProvider()) { entry in
            StreakComplicationView(entry: entry)
        }
        .configurationDisplayName("Streak")
        .description("Shows your completion streak.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}

// MARK: - Completion Ring Complication

struct CompletionRingEntry: TimelineEntry {
    let date: Date
    let completed: Int
    let total: Int
}

struct CompletionRingProvider: TimelineProvider {
    func placeholder(in context: Context) -> CompletionRingEntry {
        CompletionRingEntry(date: Date(), completed: 4, total: 7)
    }

    func getSnapshot(in context: Context, completion: @escaping (CompletionRingEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CompletionRingEntry>) -> Void) {
        let data = loadScheduleData()
        let entry = CompletionRingEntry(
            date: Date(),
            completed: data?.completedToday ?? 0,
            total: data?.totalToday ?? 0
        )
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func loadScheduleData() -> WatchScheduleData? {
        guard let data = UserDefaults.standard.data(forKey: "watchScheduleCache") else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WatchScheduleData.self, from: data)
    }
}

struct CompletionRingComplicationView: View {
    let entry: CompletionRingEntry

    private var fraction: Double {
        guard entry.total > 0 else { return 0 }
        return Double(entry.completed) / Double(entry.total)
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 4)

            // Progress ring
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Center text
            VStack(spacing: 0) {
                Text("\(entry.completed)")
                    .font(.system(size: 14, weight: .bold))
                Text("/\(entry.total)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct CompletionRingComplication: Widget {
    let kind = "CompletionRingComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CompletionRingProvider()) { entry in
            CompletionRingComplicationView(entry: entry)
        }
        .configurationDisplayName("Progress")
        .description("Shows today's task completion.")
        .supportedFamilies([.accessoryCircular])
    }
}

#endif
