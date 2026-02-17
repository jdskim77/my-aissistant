import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct TodayProgressEntry: TimelineEntry {
    let date: Date
    let tasksCompleted: Int
    let tasksTotal: Int
    let topPending: [String]
}

// MARK: - Timeline Provider

struct TodayProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayProgressEntry {
        TodayProgressEntry(date: Date(), tasksCompleted: 3, tasksTotal: 7, topPending: ["Review proposal", "Gym session"])
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (TodayProgressEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TodayProgressEntry>) -> Void) {
        // In production, read from shared App Group SwiftData container
        let entry = TodayProgressEntry(
            date: Date(),
            tasksCompleted: 0,
            tasksTotal: 0,
            topPending: []
        )
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }
}

// MARK: - Widget View

struct TodayProgressWidgetView: View {
    let entry: TodayProgressEntry

    private var progress: Double {
        guard entry.tasksTotal > 0 else { return 0 }
        return Double(entry.tasksCompleted) / Double(entry.tasksTotal)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: 60, height: 60)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(entry.tasksCompleted)")
                        .font(.system(size: 18, weight: .bold))
                    Text("/\(entry.tasksTotal)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            // Task list
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
                    ForEach(entry.topPending.prefix(3), id: \.self) { task in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 5, height: 5)
                            Text(task)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
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
        .supportedFamilies([.systemMedium])
    }
}
