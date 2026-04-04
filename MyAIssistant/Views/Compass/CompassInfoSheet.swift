import SwiftUI

/// Explains how the Life Compass works — shown via the ℹ️ button on the Compass tab.
struct CompassInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Hero
                    VStack(spacing: 12) {
                        Image(systemName: "safari")
                            .font(.system(size: 44))
                            .foregroundColor(AppColors.accent)

                        Text("How Life Compass Works")
                            .font(AppFonts.heading(22))
                            .foregroundColor(AppColors.textPrimary)

                        Text("Your Compass tracks balance across four dimensions of your life — not to judge, but to help you tune.")
                            .font(AppFonts.body(15))
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    // The Four Dimensions
                    infoSection(title: "The Four Dimensions") {
                        dimensionRow(.physical, description: "Exercise, sleep, nutrition, healthcare")
                        dimensionRow(.mental, description: "Learning, creative work, problem-solving")
                        dimensionRow(.emotional, description: "Relationships, social time, self-care")
                        dimensionRow(.spiritual, description: "Meditation, gratitude, service, helping others")
                    }

                    // How Scores Work
                    infoSection(title: "How Scores Work") {
                        Text("Your weekly score (0–10) for each dimension blends three signals:")
                            .font(AppFonts.body(14))
                            .foregroundColor(AppColors.textSecondary)

                        scoringRow(percent: "30%", label: "Activity", detail: "Effort-weighted task completion toward your personal target")
                        scoringRow(percent: "40%", label: "Satisfaction", detail: "How you rate each dimension in your evening check-ins (1–5)")
                        scoringRow(percent: "30%", label: "Consistency", detail: "How many days this week you had activity in each area")
                    }

                    // Balance Score
                    infoSection(title: "Balance Score") {
                        Text("Measures how evenly distributed your four dimensions are. Equal attention scores higher than one area dominating.")
                            .font(AppFonts.body(14))
                            .foregroundColor(AppColors.textSecondary)

                        HStack(spacing: 16) {
                            scoreExample(value: "8+", label: "Balanced across\nall four", color: AppColors.completionGreen)
                            scoreExample(value: "2-4", label: "One dominates,\nothers starve", color: AppColors.gold)
                        }

                        Text("The goal isn't perfection — it's awareness.")
                            .font(AppFonts.body(14))
                            .foregroundColor(AppColors.textSecondary)
                            .italic()
                    }

                    // Balance Streak
                    infoSection(title: "Balance Streak") {
                        HStack(spacing: 8) {
                            Image(systemName: "flame.fill")
                                .foregroundColor(AppColors.gold)
                            Text("Consecutive weeks where all four dimensions stay above 3/10. Maintaining balance over time builds your streak.")
                                .font(AppFonts.body(14))
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }

                    // Season Goals
                    infoSection(title: "Season Goals") {
                        HStack(spacing: 8) {
                            Image(systemName: "target")
                                .foregroundColor(AppColors.accent)
                            Text("Pick one dimension to intentionally focus on for 4 weeks. Nudges will prioritize that area, and your Compass tracks your progress.")
                                .font(AppFonts.body(14))
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }

                    // Tips
                    infoSection(title: "Tips") {
                        tipRow(icon: "tag.fill", text: "Tag your tasks with dimensions when creating them — this feeds the Compass")
                        tipRow(icon: "moon.stars.fill", text: "Do the evening check-in — it takes 3 seconds and makes scores more accurate")
                        tipRow(icon: "calendar", text: "Check your Compass weekly, not daily — balance is a weekly rhythm")
                        tipRow(icon: "hand.thumbsup.fill", text: "A \"low\" dimension isn't bad — it might mean this week's focus is elsewhere intentionally")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        Haptics.light()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Components

    private func infoSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppFonts.heading(16))
                .foregroundColor(AppColors.textPrimary)
            content()
        }
    }

    private func dimensionRow(_ dimension: LifeDimension, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: dimension.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(dimension.color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(dimension.label)
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(AppColors.textPrimary)
                Text(description)
                    .font(AppFonts.body(13))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func scoringRow(percent: String, label: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(percent)
                .font(AppFonts.heading(15))
                .foregroundColor(AppColors.accent)
                .frame(width: 40, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppFonts.bodyMedium(14))
                    .foregroundColor(AppColors.textPrimary)
                Text(detail)
                    .font(AppFonts.body(13))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    private func scoreExample(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(AppFonts.heading(24))
                .foregroundColor(color)
            Text(label)
                .font(AppFonts.caption(11))
                .foregroundColor(AppColors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(color.opacity(0.08))
        .cornerRadius(12)
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppColors.accent)
                .frame(width: 24)
                .padding(.top, 2)

            Text(text)
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.vertical, 2)
    }
}
