#if os(watchOS)
import SwiftUI
import WatchKit

struct WatchTodayView: View {
    var connectivity: WatchConnectivityManager
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if let data = connectivity.scheduleData, !data.tasks.isEmpty {
                scheduleContent(data)
            } else if !hasLoaded {
                loadingState
            } else {
                emptyState
            }
        }
        .navigationTitle("Today")
        .onAppear { connectivity.requestUpdate() }
        .task {
            try? await Task.sleep(for: .seconds(2))
            hasLoaded = true
        }
        .onChange(of: connectivity.scheduleData != nil) { _, hasData in
            if hasData { hasLoaded = true }
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Syncing…")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - Schedule Content

    private func scheduleContent(_ data: WatchScheduleData) -> some View {
        List {
            // Progress + streak header
            Section {
                progressHeader(data)
                    .listRowBackground(Color.clear)
            }

            // Up Next
            if let upNext = connectivity.upNextTask {
                Section {
                    NavigationLink(value: upNext) {
                        upNextCard(upNext)
                    }
                    .listRowBackground(Color.accentColor.opacity(0.15))
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            WKInterfaceDevice.current().play(.success)
                            connectivity.toggleTaskCompletion(upNext.id)
                        } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        .tint(.green)
                    }
                }
            }

            // Remaining active tasks
            let remaining = connectivity.activeTasks.filter { $0.id != connectivity.upNextTask?.id }
            if !remaining.isEmpty {
                Section {
                    ForEach(remaining) { task in
                        NavigationLink(value: task) {
                            taskRow(task)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                WKInterfaceDevice.current().play(.success)
                                connectivity.deleteTask(task.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                WKInterfaceDevice.current().play(.success)
                                connectivity.toggleTaskCompletion(task.id)
                            } label: {
                                Label("Done", systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                    }
                }
            }

            // Completed + streak
            if data.completedToday > 0 || data.streakDays > 0 {
                Section {
                    if data.completedToday > 0 {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.footnote)
                            Text("\(data.completedToday) completed")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    if data.streakDays > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.orange)
                                .font(.footnote)
                            Text("\(data.streakDays)-day streak")
                                .font(.footnote.weight(.medium))
                                .foregroundColor(.orange)
                        }
                    }
                }
            }

            // Wisdom
            if let quote = data.quoteText {
                Section {
                    wisdomCard(quote: quote, author: data.quoteAuthor)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.carousel)
    }

    // MARK: - Progress Header

    private func progressHeader(_ data: WatchScheduleData) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                    .frame(width: 36, height: 36)
                Circle()
                    .trim(from: 0, to: connectivity.completionFraction)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))
                Text("\(data.completedToday)/\(data.totalToday)")
                    .font(.system(size: 9, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(data.totalToday - data.completedToday) remaining")
                    .font(.subheadline.weight(.semibold))
                if let nextCheckIn = data.nextCheckIn {
                    Text("\(nextCheckIn) check-in")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(data.completedToday) of \(data.totalToday) tasks done. \(data.totalToday - data.completedToday) remaining.")
    }

    // MARK: - Up Next Card

    private func upNextCard(_ task: WatchScheduleData.WatchTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                Text("UP NEXT")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.accentColor)
            }

            HStack(spacing: 8) {
                Button {
                    WKInterfaceDevice.current().play(.success)
                    connectivity.toggleTaskCompletion(task.id)
                } label: {
                    ZStack {
                        Circle()
                            .stroke(task.done ? Color.green : Color.accentColor, lineWidth: 2)
                            .frame(width: 22, height: 22)
                        if task.done {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.done ? "Mark incomplete" : "Mark complete")

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.headline)
                        .lineLimit(2)
                        .strikethrough(task.done)

                    if task.hasTime {
                        Text(task.timeString)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Task Row

    private func taskRow(_ task: WatchScheduleData.WatchTask) -> some View {
        HStack(spacing: 8) {
            Button {
                WKInterfaceDevice.current().play(.success)
                connectivity.toggleTaskCompletion(task.id)
            } label: {
                ZStack {
                    Circle()
                        .stroke(task.done ? Color.green : priorityColor(task.priorityRaw), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if task.done {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.done ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .strikethrough(task.done)
                    .foregroundColor(task.done ? .secondary : .primary)

                if task.hasTime {
                    Text(task.timeString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if task.isCalendarEvent {
                Image(systemName: "calendar")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Wisdom Card

    private func wisdomCard(quote: String, author: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(quote)
                .font(.caption.italic())
                .foregroundColor(.secondary)
                .lineLimit(3)
            if let author {
                Text("— \(author)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.max")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("No tasks today")
                .font(.headline)
            Text("Tap + to add a task")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - Helpers

    private func priorityColor(_ raw: String) -> Color {
        switch raw {
        case "High": return .red
        case "Medium": return .orange
        default: return .blue
        }
    }
}

#endif
