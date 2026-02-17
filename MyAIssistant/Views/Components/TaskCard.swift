import SwiftUI

struct TaskCard: View {
    let task: TaskItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(task.done ? AppColors.accentWarm : AppColors.border)
            }
            .buttonStyle(.plain)

            Text(task.icon)
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(task.done ? AppColors.textMuted : AppColors.textPrimary)
                    .strikethrough(task.done)

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            PriorityBadge(priority: task.priority)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.card)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
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
