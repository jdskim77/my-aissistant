#if os(watchOS)
import SwiftUI
import WatchKit
import WatchConnectivity

struct WatchTasksListView: View {
    var connectivity: WatchConnectivityManager

    @State private var retryFailedAt: Date?

    private var retryFeedback: String {
        guard let stamp = retryFailedAt,
              Date().timeIntervalSince(stamp) < 3 else { return "Try again" }
        return "Still offline"
    }

    var body: some View {
        Group {
            if connectivity.scheduleData != nil {
                let today = connectivity.todayTasks
                if today.isEmpty {
                    emptyState
                } else {
                    content(today)
                }
            } else if connectivity.hasAttemptedSync {
                unreachableState
            } else {
                loadingState
            }
        }
        .navigationTitle("Tasks")
        .onAppear { connectivity.requestUpdate() }
    }

    // MARK: - Ideal

    private func content(_ tasks: [WatchScheduleData.WatchTask]) -> some View {
        let sorted = sortedForDisplay(tasks)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(sorted) { task in
                    row(task)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }

    // Row layout mirrors WatchTodayView.inlineNextRow: the 44pt checkbox is a
    // SIBLING of the NavigationLink, not a child, so tapping the checkbox
    // never propagates to the row-level push. VoiceOver gets one focusable
    // element per task with a custom action for completion toggle.
    private func row(_ task: WatchScheduleData.WatchTask) -> some View {
        HStack(alignment: .center, spacing: 6) {
            checkbox(for: task)
                .accessibilityHidden(true)

            NavigationLink(value: task) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.callout)
                            .lineLimit(2)
                            .strikethrough(task.done)
                            .foregroundStyle(task.done ? .secondary : .primary)
                        if task.hasTime {
                            Text(task.timeString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accentColor(for: task).opacity(task.done ? 0.05 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accentColor(for: task).opacity(task.done ? 0.10 : 0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: task))
        .accessibilityHint("Opens task details")
        .accessibilityAction(named: Text(task.done ? "Mark incomplete" : "Mark complete")) {
            handleToggle(task)
        }
    }

    private func checkbox(for task: WatchScheduleData.WatchTask) -> some View {
        Button {
            handleToggle(task)
        } label: {
            ZStack {
                Circle()
                    .stroke(task.done ? Color.green : accentColor(for: task), lineWidth: 2)
                    .frame(width: 22, height: 22)
                if task.done {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Completion handling

    private func handleToggle(_ task: WatchScheduleData.WatchTask) {
        let willBeDone = !task.done
        // Celebratory haptic only on forward completion; undo gets the
        // quieter selection haptic (parity with iPhone + Today view).
        WKInterfaceDevice.current().play(willBeDone ? .success : .click)
        connectivity.toggleTaskCompletion(task.id)
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Syncing…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sun.max")
                .font(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Nothing on today")
                .font(.callout)
                .fontWeight(.medium)
            Text("Ask the AI to add one, or swipe right to check in.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unreachableState: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.slash")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Can't reach iPhone")
                .font(.callout)
            Text("Open Thrivn on iPhone to sync.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                WKInterfaceDevice.current().play(.click)
                connectivity.requestUpdate()
                // Only surface "Still offline" when the session actually
                // remained unreachable — a successful re-sync should leave
                // the label alone so this view transitions out of the
                // unreachable state naturally.
                if !WCSession.default.isReachable {
                    WKInterfaceDevice.current().play(.failure)
                    retryFailedAt = Date()
                    // Schedule a re-render so the label flips back after the
                    // 3-second window without needing another tap (the
                    // computed `retryFeedback` reads `Date()` and otherwise
                    // wouldn't re-evaluate on its own).
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        if let stamp = retryFailedAt,
                           Date().timeIntervalSince(stamp) >= 3 {
                            retryFailedAt = nil
                        }
                    }
                }
            } label: {
                Text(retryFeedback)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 36)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    /// Active first (by scheduled time), completed last. Tasks without a
    /// time fall to the end of their group.
    private func sortedForDisplay(_ tasks: [WatchScheduleData.WatchTask]) -> [WatchScheduleData.WatchTask] {
        tasks.sorted { lhs, rhs in
            if lhs.done != rhs.done { return !lhs.done && rhs.done }
            if lhs.hasTime != rhs.hasTime { return lhs.hasTime && !rhs.hasTime }
            return lhs.date < rhs.date
        }
    }

    /// Dimension-tinted color (matches Today's inline row) falling back to
    /// priority-based tint when the task has no dimensions attached, so the
    /// same task reads the same across pages.
    private func accentColor(for task: WatchScheduleData.WatchTask) -> Color {
        if let dim = primaryDimension(for: task) {
            return dim.color
        }
        switch task.priorityRaw {
        case "High":   return .red
        case "Medium": return .orange
        default:       return .accentColor
        }
    }

    private func primaryDimension(for task: WatchScheduleData.WatchTask) -> WatchDimension? {
        guard let raw = task.dimensionsRaw else { return nil }
        return raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .compactMap(WatchDimension.from(rawValue:))
            .first
    }

    private func accessibilityLabel(for task: WatchScheduleData.WatchTask) -> String {
        var parts: [String] = [task.title]
        if task.hasTime { parts.append("at \(task.timeString)") }
        parts.append(task.done ? "completed" : "not completed")
        return parts.joined(separator: ", ")
    }
}
#endif
