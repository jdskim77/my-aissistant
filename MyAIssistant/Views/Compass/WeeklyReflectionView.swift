import SwiftUI

/// Weekly reflection sheet: shows the Compass radar chart paired with
/// an open-ended reflection question. Appears Sunday evening.
struct WeeklyReflectionView: View {
    @Environment(\.dismiss) private var dismiss
    let balanceManager: BalanceManager
    @State private var reflectionText: String
    @State private var saved = false

    init(balanceManager: BalanceManager) {
        self.balanceManager = balanceManager
        self._reflectionText = State(initialValue: balanceManager.loadWeeklyReflectionText() ?? "")
    }

    private var breakdowns: [LifeDimension: BalanceManager.DimensionBreakdown] { balanceManager.weeklyBreakdowns() }
    private var balanceScoreValue: Double { balanceManager.balanceScore() }
    private var reflectionPrompt: String { balanceManager.weeklyReflectionPrompt() ?? "How balanced did your week feel?" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    // Compass snapshot
                    CompassView(
                        breakdowns: breakdowns,
                        balanceScoreValue: balanceScoreValue,
                        balanceStreak: balanceManager.balanceStreak(),
                        hasRealData: breakdowns.values.contains(where: { $0.composite > 0 })
                    )

                    // Reflection question
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "thought.bubble")
                                .font(AppFonts.label(13))
                                .foregroundColor(AppColors.accent)
                            Text("Weekly Reflection")
                                .font(AppFonts.heading(15))
                                .foregroundColor(AppColors.textPrimary)
                        }

                        Text(reflectionPrompt)
                            .font(AppFonts.body(15))
                            .foregroundColor(AppColors.textSecondary)
                            .italic()

                        TextField("Your thoughts (optional)...", text: $reflectionText, axis: .vertical)
                            .font(AppFonts.body(15))
                            .lineLimit(3...6)
                            .padding(12)
                            .background(AppColors.surface)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )
                    }

                    // Season goal check-in
                    if let goal = balanceManager.activeSeasonGoal() {
                        seasonGoalCard(goal)
                    }

                    // Action buttons
                    VStack(spacing: 10) {
                        if saved {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AppColors.completionGreen)
                                Text("Reflection saved")
                                    .font(AppFonts.bodyMedium(15))
                                    .foregroundColor(AppColors.completionGreen)
                            }
                            .padding(.vertical, 16)
                            .task {
                                try? await Task.sleep(for: .seconds(1.2))
                                dismiss()
                            }
                        } else {
                            Button {
                                Haptics.success()
                                withAnimation(.spring(response: 0.3)) {
                                    saved = true
                                }
                                // Save reflection text and mark as done
                                balanceManager.saveWeeklyReflection(reflectionText)

                            } label: {
                                Text(reflectionText.isEmpty ? "Done" : "Save Reflection")
                                    .font(AppFonts.bodyMedium(16))
                                    .foregroundColor(AppColors.onAccent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(AppColors.accent)
                                    .cornerRadius(16)
                            }
                        }

                        Button {
                            Haptics.light()
                            dismiss()
                        } label: {
                            Text("Skip this week")
                                .font(AppFonts.body(14))
                                .foregroundColor(AppColors.textMuted)
                                .frame(minHeight: 44)
                        }
                        .accessibilityLabel("Skip weekly reflection")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Week in Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        Haptics.light()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Components

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.checkmark")
                .font(AppFonts.display(32))
                .foregroundColor(AppColors.accent)
            Text("Your Week")
                .font(AppFonts.heading(20))
                .foregroundColor(AppColors.textPrimary)
        }
    }

    private func seasonGoalCard(_ goal: SeasonGoal) -> some View {
        HStack(spacing: 12) {
            Image(systemName: goal.dimension.icon)
                .font(AppFonts.heading(18).weight(.medium))
                .foregroundColor(goal.dimension.color)
                .frame(width: 36, height: 36)
                .background(goal.dimension.color.opacity(0.1))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 3) {
                Text("Season Goal: \(goal.dimension.label)")
                    .font(AppFonts.bodyMedium(14))
                    .foregroundColor(AppColors.textPrimary)

                let score = balanceManager.seasonGoalProgress() ?? 0
                Text("\(String(format: "%.1f", min(10, score)))/10 this week · \(goal.daysRemaining) days remaining")
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            // Mini progress ring
            ZStack {
                Circle()
                    .stroke(AppColors.border, lineWidth: 3)
                    .frame(width: 28, height: 28)
                Circle()
                    .trim(from: 0, to: goal.progress)
                    .stroke(goal.dimension.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(14)
        .background(AppColors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(goal.dimension.color.opacity(0.2), lineWidth: 1)
        )
    }

    /// Whether the weekly reflection has already been done this week.
    /// Prefer calling balanceManager.hasReflectedThisWeek() when available.
    static func hasReflectedThisWeek() -> Bool {
        let cal = Calendar.current
        let key = "weeklyReflection_\(cal.component(.weekOfYear, from: Date()))_\(cal.component(.yearForWeekOfYear, from: Date()))"
        return UserDefaults.standard.bool(forKey: key)
    }
}
