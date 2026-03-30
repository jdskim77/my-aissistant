import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct TodayProgressEntry: TimelineEntry {
    let date: Date
    let tasksCompleted: Int
    let tasksTotal: Int
    let topPending: [WidgetData.WidgetTask]
    let quoteText: String?
    let quoteAuthor: String?
}

// MARK: - Timeline Provider

struct TodayProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayProgressEntry {
        TodayProgressEntry(
            date: Date(),
            tasksCompleted: 3,
            tasksTotal: 7,
            topPending: [
                .init(title: "Review proposal", priority: "High", time: "10:00 AM"),
                .init(title: "Gym session", priority: "Medium", time: "6:00 PM")
            ],
            quoteText: "The secret of getting ahead is getting started.",
            quoteAuthor: "Mark Twain"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (TodayProgressEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TodayProgressEntry>) -> Void) {
        let entry = loadEntry()
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }

    private func loadEntry() -> TodayProgressEntry {
        if let data = WidgetData.load() {
            return TodayProgressEntry(
                date: Date(),
                tasksCompleted: data.tasksCompleted,
                tasksTotal: data.tasksTotal,
                topPending: data.topPending,
                quoteText: data.quoteText,
                quoteAuthor: data.quoteAuthor
            )
        }
        return TodayProgressEntry(date: Date(), tasksCompleted: 0, tasksTotal: 0, topPending: [], quoteText: nil, quoteAuthor: nil)
    }
}

// MARK: - Widget View

struct TodayProgressWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TodayProgressEntry

    private var progress: Double {
        guard entry.tasksTotal > 0 else { return 0 }
        return Double(entry.tasksCompleted) / Double(entry.tasksTotal)
    }

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        default:
            mediumView
        }
    }

    // MARK: - Medium

    private var mediumView: some View {
        HStack(spacing: 16) {
            progressRing(size: 60, lineWidth: 8, fontSize: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Progress")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                if entry.topPending.isEmpty && entry.tasksTotal == 0 {
                    Text("No tasks today")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else if entry.topPending.isEmpty {
                    Text("All done!")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                } else {
                    ForEach(Array(entry.topPending.prefix(3).enumerated()), id: \.offset) { _, task in
                        taskRow(task)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Large

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top: progress + summary
            HStack(spacing: 14) {
                progressRing(size: 52, lineWidth: 6, fontSize: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's Progress")
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(entry.tasksCompleted) of \(entry.tasksTotal) done")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // Tasks
            if entry.topPending.isEmpty && entry.tasksTotal == 0 {
                Text("No tasks today")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else if entry.topPending.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("All tasks completed!")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.green)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(entry.topPending.prefix(5).enumerated()), id: \.offset) { _, task in
                        taskRow(task)
                    }
                }
            }

            Spacer()

            // Daily wisdom quote
            if let quote = entry.quoteText, let author = entry.quoteAuthor {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Daily Wisdom")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.orange)

                    Text("\"\(quote)\"")
                        .font(.system(size: 11, design: .serif))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .italic()

                    Text("- \(author)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Shared Components

    private func progressRing(size: CGFloat, lineWidth: CGFloat, fontSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(entry.tasksCompleted)")
                    .font(.system(size: fontSize, weight: .bold))
                Text("/\(entry.tasksTotal)")
                    .font(.system(size: fontSize * 0.6))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func taskRow(_ task: WidgetData.WidgetTask) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(priorityColor(task.priority))
                .frame(width: 6, height: 6)
            Text(task.title)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            if let time = task.time {
                Text(time)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "High": return .red
        case "Medium": return .orange
        default: return .blue
        }
    }
}

// MARK: - Widget Configuration

struct TodayProgressWidget: Widget {
    let kind = "TodayProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProgressProvider()) { entry in
            TodayProgressWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Progress")
        .description("Track your daily task completion.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
