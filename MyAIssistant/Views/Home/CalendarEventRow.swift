import SwiftUI

struct CalendarEventRow: View {
    let task: TaskItem
    let onToggle: () -> Void

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: task.date)
    }

    private var sourceLabel: String {
        guard let extID = task.externalCalendarID else { return "Calendar" }
        if extID.hasPrefix("google:") { return "Google Calendar" }
        return "Apple Calendar"
    }

    private var checkboxColor: Color {
        task.done ? AppColors.completionGreen : AppColors.skyBlue
    }

    var body: some View {
        HStack(spacing: 0) {
            // Completion checkbox
            Button {
                Haptics.success()
                onToggle()
            } label: {
                ZStack {
                    Circle()
                        .stroke(checkboxColor, lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if task.done {
                        Circle()
                            .fill(checkboxColor)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(AppFonts.label(12))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.done ? "Mark \(task.title) incomplete" : "Complete \(task.title)")

            // Time column
            Text(timeText)
                .font(AppFonts.bodyMedium(13))
                .foregroundColor(task.done ? AppColors.textMuted : AppColors.textSecondary)
                .frame(width: 56, alignment: .trailing)

            // Blue vertical bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(task.done ? AppColors.completionGreen : AppColors.skyBlue)
                .frame(width: 3, height: 36)
                .padding(.horizontal, 10)

            // Event info
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(task.done ? AppColors.textMuted : AppColors.textPrimary)
                    .strikethrough(task.done)
                    .lineLimit(1)
                Text(sourceLabel)
                    .font(AppFonts.caption(11))
                    .foregroundColor(task.done ? AppColors.textMuted : AppColors.skyBlue)
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .listRowBackground(task.done ? AppColors.card : AppColors.skyBlue.opacity(0.05))
    }
}
