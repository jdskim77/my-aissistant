import SwiftUI
import SwiftData

struct ActivityTimelineView: View {
    @Environment(\.patternEngine) private var patternEngine

    private var categorySummary: [(category: String, count: Int)] {
        patternEngine?.activityCategorySummary() ?? []
    }

    private var recentActivities: [ActivityEntry] {
        patternEngine?.recentActivities(days: 30) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Activity Tracker")
                .font(AppFonts.heading(16))
                .foregroundColor(AppColors.textPrimary)

            if recentActivities.isEmpty {
                emptyState
            } else {
                // Category pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categorySummary, id: \.category) { item in
                            HStack(spacing: 4) {
                                Text(iconFor(category: item.category))
                                    .font(.system(size: 12))
                                Text(item.category)
                                    .font(AppFonts.bodyMedium(12))
                                Text("\(item.count)")
                                    .font(AppFonts.caption(11))
                                    .foregroundColor(AppColors.textMuted)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(colorFor(category: item.category).opacity(0.12))
                            .cornerRadius(12)
                        }
                    }
                }

                // Recent activities list
                VStack(spacing: 8) {
                    ForEach(recentActivities.prefix(10), id: \.id) { entry in
                        HStack(spacing: 10) {
                            Text(iconFor(category: entry.category))
                                .font(.system(size: 14))
                                .frame(width: 28, height: 28)
                                .background(colorFor(category: entry.category).opacity(0.12))
                                .cornerRadius(8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.activity)
                                    .font(AppFonts.body(13))
                                    .foregroundColor(AppColors.textPrimary)
                                    .lineLimit(1)

                                Text(formatDate(entry.date))
                                    .font(AppFonts.caption(11))
                                    .foregroundColor(AppColors.textMuted)
                            }

                            Spacer()

                            Text(entry.category)
                                .font(AppFonts.caption(10))
                                .foregroundColor(colorFor(category: entry.category))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(colorFor(category: entry.category).opacity(0.08))
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundColor(AppColors.textMuted)
            Text("No activities tracked yet")
                .font(AppFonts.body(13))
                .foregroundColor(AppColors.textSecondary)
            Text("Chat with your assistant about what you've been up to and it'll start tracking automatically.")
                .font(AppFonts.caption(11))
                .foregroundColor(AppColors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func iconFor(category: String) -> String {
        switch category.lowercased() {
        case "exercise", "fitness": return "🏃"
        case "social": return "👥"
        case "work": return "💼"
        case "learning", "education": return "📚"
        case "creative": return "🎨"
        case "wellness", "health": return "🧘"
        case "errands": return "🛒"
        case "food", "cooking", "dining": return "🍽️"
        case "travel": return "✈️"
        case "entertainment": return "🎬"
        default: return "📌"
        }
    }

    private func colorFor(category: String) -> Color {
        switch category.lowercased() {
        case "exercise", "fitness": return AppColors.coral
        case "social": return AppColors.skyBlue
        case "work": return AppColors.accent
        case "learning", "education": return AppColors.gold
        case "creative": return AppColors.afternoon
        case "wellness", "health": return AppColors.completionGreen
        case "errands": return AppColors.accentWarm
        case "food", "cooking", "dining": return AppColors.morning
        case "travel": return AppColors.skyBlue
        case "entertainment": return AppColors.night
        default: return AppColors.textSecondary
        }
    }
}
