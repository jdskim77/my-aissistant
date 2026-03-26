import SwiftUI

struct TaskCard: View {
    let task: TaskItem
    var isOverdue: Bool = false
    let onToggle: () -> Void

    @State private var isExpanded = false

    private var checkboxColor: Color {
        task.done ? AppColors.completionGreen : AppColors.checkboxColor(task.priority)
    }

    private var timeText: String? {
        let hour = Calendar.current.component(.hour, from: task.date)
        let minute = Calendar.current.component(.minute, from: task.date)
        if hour == 0 && minute == 0 { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: task.date)
    }

    private var overdueDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: task.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 12) {
                // Priority-colored checkbox
                Button(action: onToggle) {
                    ZStack {
                        Circle()
                            .stroke(checkboxColor, lineWidth: 2)
                            .frame(width: 24, height: 24)

                        if task.done {
                            Circle()
                                .fill(checkboxColor)
                                .frame(width: 24, height: 24)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(.plain)

                // Title + time/overdue
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(task.done ? AppColors.textMuted : AppColors.textPrimary)
                        .strikethrough(task.done)
                        .lineLimit(isExpanded ? nil : 1)

                    HStack(spacing: 4) {
                        if isOverdue && !task.done {
                            Text(overdueDateText)
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.overdueRed)
                        } else if let time = timeText, !task.done {
                            Text(time)
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.textMuted)
                        }
                        if task.recurrence != .none && !task.done {
                            Image(systemName: "repeat")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppColors.accent)
                        }
                    }
                }

                Spacer()

                // Priority dot
                if !task.done {
                    Circle()
                        .fill(AppColors.checkboxColor(task.priority))
                        .frame(width: 8, height: 8)
                }

                // Expand chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.textMuted)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.vertical, 10)

            // Expanded details
            if isExpanded {
                Divider()
                    .padding(.leading, 36)

                VStack(alignment: .leading, spacing: 10) {
                    if !task.notes.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "note.text")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.textMuted)
                                .frame(width: 20)
                            Text(task.notes)
                                .font(AppFonts.body(14))
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }

                    HStack(spacing: 8) {
                        PriorityBadge(priority: task.priority)

                        Text(task.category.rawValue)
                            .font(AppFonts.label(11))
                            .foregroundColor(AppColors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColors.border.opacity(0.3))
                            .cornerRadius(6)

                        if task.recurrence != .none {
                            HStack(spacing: 3) {
                                Image(systemName: "repeat")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(task.recurrence.rawValue)
                                    .font(AppFonts.label(11))
                            }
                            .foregroundColor(AppColors.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColors.accentLight)
                            .cornerRadius(6)
                        }

                        Spacer()

                        Text(task.date.formatted(as: "MMM d, h:mm a"))
                            .font(AppFonts.caption(12))
                            .foregroundColor(AppColors.textMuted)
                    }
                }
                .padding(.leading, 36)
                .padding(.vertical, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
        .listRowBackground(
            isOverdue && !task.done
                ? AppColors.overdueBg
                : AppColors.card
        )
    }
}

struct PriorityBadge: View {
    let priority: TaskPriority

    var body: some View {
        Text(priority.rawValue)
            .font(AppFonts.label(11))
            .foregroundColor(AppColors.priorityColor(priority))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.priorityColor(priority).opacity(0.12))
            .cornerRadius(6)
    }
}
