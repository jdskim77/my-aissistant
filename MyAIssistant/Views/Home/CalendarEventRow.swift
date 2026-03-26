import SwiftUI

struct CalendarEventRow: View {
    let task: TaskItem

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

    var body: some View {
        HStack(spacing: 0) {
            // Time column
            Text(timeText)
                .font(AppFonts.bodyMedium(13))
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 56, alignment: .trailing)

            // Blue vertical bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(AppColors.skyBlue)
                .frame(width: 3, height: 36)
                .padding(.horizontal, 10)

            // Event info
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                Text(sourceLabel)
                    .font(AppFonts.caption(11))
                    .foregroundColor(AppColors.skyBlue)
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .listRowBackground(AppColors.skyBlue.opacity(0.05))
    }
}
