#if os(watchOS)
import SwiftUI
import WatchKit

struct WatchTaskDetailView: View {
    let task: WatchScheduleData.WatchTask
    var connectivity: WatchConnectivityManager
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var didAct = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Status + Title
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        guard !didAct else { return }
                        didAct = true
                        WKInterfaceDevice.current().play(.success)
                        connectivity.toggleTaskCompletion(task.id)
                        dismiss()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(task.done ? Color.green : priorityColor, lineWidth: 2.5)
                                .frame(width: 26, height: 26)
                            if task.done {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 26, height: 26)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(task.done ? "Mark incomplete" : "Mark complete")

                    Text(task.title)
                        .font(.headline)
                        .lineLimit(4)
                        .strikethrough(task.done)
                        .foregroundColor(task.done ? .secondary : .primary)
                }

                Divider()

                // Details
                detailRow(icon: "flag.fill", label: "Priority", value: task.priorityRaw, color: priorityColor)

                if task.hasTime {
                    detailRow(icon: "clock.fill", label: "Time", value: task.timeString, color: .blue)
                }

                detailRow(icon: "folder.fill", label: "Category", value: task.categoryRaw, color: .purple)

                if task.isCalendarEvent {
                    detailRow(icon: "calendar", label: "Source", value: "Calendar", color: .blue)
                }

                if let recurrence = task.recurrenceRaw, !recurrence.isEmpty, recurrence != "none" {
                    detailRow(icon: "repeat", label: "Repeats", value: recurrence.capitalized, color: .orange)
                }

                Divider()

                // Actions
                if !task.done {
                    Button {
                        guard !didAct else { return }
                        didAct = true
                        WKInterfaceDevice.current().play(.success)
                        connectivity.toggleTaskCompletion(task.id)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Complete")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .tint(.green)
                    .disabled(didAct)
                }

                if !task.isCalendarEvent {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(didAct)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Task")
        .confirmationDialog("Delete this task?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                guard !didAct else { return }
                didAct = true
                WKInterfaceDevice.current().play(.click)
                connectivity.deleteTask(task.id)
                dismiss()
            }
        }
    }

    private var priorityColor: Color {
        switch task.priorityRaw {
        case "High": .red
        case "Medium": .orange
        default: .blue
        }
    }

    private func detailRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
