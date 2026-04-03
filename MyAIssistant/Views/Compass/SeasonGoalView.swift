import SwiftUI

/// Sheet for starting or viewing a Season Goal — a 4-week focus on one life dimension.
struct SeasonGoalView: View {
    @Environment(\.dismiss) private var dismiss
    let balanceManager: BalanceManager

    @State private var selectedDimension: LifeDimension?
    @State private var intention = ""
    @State private var showConfirmation = false
    @State private var showEndGoalConfirmation = false

    private var existingGoal: SeasonGoal? { balanceManager.activeSeasonGoal() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let goal = existingGoal {
                        activeGoalContent(goal)
                    } else {
                        newGoalFlow
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 32)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Season Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        Haptics.light()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("End Season Goal?", isPresented: $showEndGoalConfirmation, titleVisibility: .visible) {
                Button("End Goal Early", role: .destructive) {
                    Haptics.medium()
                    balanceManager.completeSeasonGoal()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will end your current 4-week focus. You can start a new one anytime.")
            }
        }
    }

    // MARK: - Active Goal Content

    private func activeGoalContent(_ goal: SeasonGoal) -> some View {
        VStack(spacing: 20) {
            // 1. Hero — Icon, name, intention, progress ring
            heroSection(goal)

            // 2. This Week's Performance
            performanceCard(goal)

            // 3. Weekly Trend
            weeklyTrendCard(goal)

            // 4. This Week's Tasks
            tasksCard(goal)

            // 5. AI Suggestion
            suggestionCard(goal)

            // 6. End Goal (de-emphasized)
            Button {
                Haptics.light()
                showEndGoalConfirmation = true
            } label: {
                Text("End Goal Early")
                    .font(AppFonts.caption(13))
                    .foregroundColor(AppColors.textMuted)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("End season goal early")
        }
    }

    // MARK: - 1. Hero Section

    private func heroSection(_ goal: SeasonGoal) -> some View {
        VStack(spacing: 16) {
            // Progress ring with icon
            ZStack {
                Circle()
                    .stroke(goal.dimension.color.opacity(0.15), lineWidth: 10)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: goal.progress)
                    .stroke(goal.dimension.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.5), value: goal.progress)

                VStack(spacing: 2) {
                    Image(systemName: goal.dimension.icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(goal.dimension.color)
                    Text("\(goal.daysRemaining)d")
                        .font(AppFonts.label(12))
                        .foregroundColor(AppColors.textMuted)
                }
            }

            VStack(spacing: 4) {
                Text(goal.dimension.label)
                    .font(AppFonts.heading(22))
                    .foregroundColor(AppColors.textPrimary)

                if !goal.intention.isEmpty {
                    Text("\"\(goal.intention)\"")
                        .font(AppFonts.body(15))
                        .foregroundColor(AppColors.textSecondary)
                        .italic()
                        .multilineTextAlignment(.center)
                }

                // Date range
                HStack(spacing: 4) {
                    Text(goal.startDate, style: .date)
                    Text("→")
                    Text(goal.endDate, style: .date)
                }
                .font(AppFonts.caption(11))
                .foregroundColor(AppColors.textMuted)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - 2. Performance Card (3-Signal Breakdown)

    private func performanceCard(_ goal: SeasonGoal) -> some View {
        let breakdowns = balanceManager.weeklyBreakdowns()
        let bd = breakdowns[goal.dimension] ?? BalanceManager.DimensionBreakdown(activity: 5, satisfaction: 5, consistency: 5)
        let score = bd.composite
        let points = balanceManager.thisWeekEffortPoints()[goal.dimension] ?? 0
        let target = balanceManager.personalTarget(for: goal.dimension)

        return VStack(spacing: 14) {
            HStack {
                Text("This Week")
                    .font(AppFonts.heading(15))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Text(String(format: "%.1f", min(10, score)))
                    .font(AppFonts.heading(22))
                    .foregroundColor(goal.dimension.color)
                    .monospacedDigit()
                Text("/ 10")
                    .font(AppFonts.caption(13))
                    .foregroundColor(AppColors.textMuted)
            }

            // 3 signal bars
            VStack(spacing: 10) {
                signalRow(
                    icon: "flame",
                    label: "Activity",
                    value: bd.activity,
                    detail: "\(points) / \(target) effort pts",
                    color: .green
                )
                signalRow(
                    icon: "heart.fill",
                    label: "Satisfaction",
                    value: bd.satisfaction,
                    detail: bd.satisfaction == 5 ? "No ratings yet" : String(format: "%.1f avg", bd.satisfaction / 2),
                    color: .blue
                )
                signalRow(
                    icon: "calendar",
                    label: "Consistency",
                    value: bd.consistency,
                    detail: "\(Int(bd.consistency / 10 * 7)) of 7 days active",
                    color: .orange
                )
            }
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func signalRow(icon: String, label: String, value: Double, detail: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                    .frame(width: 16)
                Text(label)
                    .font(AppFonts.bodyMedium(13))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Text(detail)
                    .font(AppFonts.caption(11))
                    .foregroundColor(AppColors.textMuted)
                Text(String(format: "%.1f", min(10, value)))
                    .font(AppFonts.label(12))
                    .foregroundColor(color)
                    .monospacedDigit()
                    .frame(width: 28, alignment: .trailing)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColors.border.opacity(0.3))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.6))
                        .frame(width: geo.size.width * min(1, value / 10))
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - 3. Weekly Trend

    private func weeklyTrendCard(_ goal: SeasonGoal) -> some View {
        let calendar = Calendar.current
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()

        // Get scores for last 4 weeks
        let weekScores: [(String, Double)] = (0..<4).reversed().map { weeksAgo in
            let weekStart = calendar.safeDate(byAdding: .day, value: -7 * weeksAgo, to: currentWeekStart)
            let scores = balanceManager.weeklyScores(for: weekStart)
            let score = scores[goal.dimension] ?? 5
            let label = weeksAgo == 0 ? "This wk" : "\(weeksAgo)w ago"
            return (label, score)
        }

        let maxScore = max(10, weekScores.map(\.1).max() ?? 10)

        return VStack(spacing: 12) {
            HStack {
                Text("4-Week Trend")
                    .font(AppFonts.heading(15))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                trendArrow(weekScores)
            }

            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(weekScores.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 6) {
                        Text(String(format: "%.1f", min(10, item.1)))
                            .font(AppFonts.label(10))
                            .foregroundColor(index == weekScores.count - 1 ? goal.dimension.color : AppColors.textMuted)
                            .monospacedDigit()

                        RoundedRectangle(cornerRadius: 4)
                            .fill(index == weekScores.count - 1 ? goal.dimension.color : goal.dimension.color.opacity(0.3))
                            .frame(height: max(8, CGFloat(item.1 / maxScore) * 60))

                        Text(item.0)
                            .font(AppFonts.caption(9))
                            .foregroundColor(AppColors.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100)
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func trendArrow(_ scores: [(String, Double)]) -> some View {
        let values = scores.map(\.1)
        guard values.count >= 2 else { return AnyView(EmptyView()) }
        let last = values.last ?? 0
        let prev = values[values.count - 2]
        let diff = last - prev

        let icon: String
        let color: Color
        let label: String

        if diff > 0.5 {
            icon = "arrow.up.right"
            color = AppColors.completionGreen
            label = "Trending up"
        } else if diff < -0.5 {
            icon = "arrow.down.right"
            color = AppColors.coral
            label = "Trending down"
        } else {
            icon = "arrow.right"
            color = AppColors.textMuted
            label = "Steady"
        }

        return AnyView(
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(AppFonts.caption(11))
            }
            .foregroundColor(color)
        )
    }

    // MARK: - 4. Tasks This Week

    private func tasksCard(_ goal: SeasonGoal) -> some View {
        let counts = balanceManager.thisWeekTaskCounts()
        let points = balanceManager.thisWeekEffortPoints()
        let taskCount = counts[goal.dimension] ?? 0
        let effortPoints = points[goal.dimension] ?? 0

        return VStack(spacing: 12) {
            HStack {
                Text("Tasks This Week")
                    .font(AppFonts.heading(15))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Text("\(taskCount) tasks, \(effortPoints) pts")
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)
            }

            if taskCount == 0 {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundColor(AppColors.textMuted)
                    Text("No \(goal.dimension.label.lowercased()) tasks completed yet this week")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                // Summary bar showing effort distribution
                HStack(spacing: 4) {
                    ForEach(EffortLevel.allCases) { level in
                        HStack(spacing: 3) {
                            Image(systemName: level.icon)
                                .font(.system(size: 10))
                            Text(level.label)
                                .font(AppFonts.caption(10))
                        }
                        .foregroundColor(AppColors.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.surface)
                        .cornerRadius(6)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - 5. AI Suggestion

    private func suggestionCard(_ goal: SeasonGoal) -> some View {
        let breakdowns = balanceManager.weeklyBreakdowns()
        let bd = breakdowns[goal.dimension] ?? BalanceManager.DimensionBreakdown(activity: 5, satisfaction: 5, consistency: 5)

        // Find weakest signal
        let signals: [(String, String, Double, String)] = [
            ("flame", "Activity", bd.activity, "Try adding a \(goal.dimension.label.lowercased()) task today — even a small one counts."),
            ("heart.fill", "Satisfaction", bd.satisfaction, "Rate your \(goal.dimension.label.lowercased()) satisfaction during your next check-in."),
            ("calendar", "Consistency", bd.consistency, "Aim for a small \(goal.dimension.label.lowercased()) activity each day — regularity beats intensity.")
        ]

        let weakest = signals.min(by: { $0.2 < $1.2 })!

        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.gold)
                Text("Suggestion")
                    .font(AppFonts.heading(14))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: weakest.0)
                        .font(.system(size: 10))
                    Text("\(weakest.1) is lowest")
                        .font(AppFonts.caption(10))
                }
                .foregroundColor(AppColors.textMuted)
            }

            Text(weakest.3)
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(AppColors.gold.opacity(0.06))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.gold.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - New Goal Flow

    private var newGoalFlow: some View {
        VStack(spacing: 20) {
            if showConfirmation {
                confirmationView
            } else {
                selectionView
            }
        }
    }

    private var selectionView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 36))
                    .foregroundColor(AppColors.accent)

                Text("Choose Your Focus")
                    .font(AppFonts.heading(20))
                    .foregroundColor(AppColors.textPrimary)

                Text("Pick one dimension to intentionally invest in for 4 weeks")
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Dimension cards with current scores
            let breakdowns = balanceManager.weeklyBreakdowns()

            ForEach(LifeDimension.scored) { dim in
                let score = breakdowns[dim]?.composite ?? 5

                Button {
                    Haptics.light()
                    withAnimation(.snappy(duration: 0.25)) {
                        selectedDimension = dim
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: dim.icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(dim.color)
                            .frame(width: 44, height: 44)
                            .background(dim.color.opacity(0.1))
                            .cornerRadius(12)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(dim.label)
                                    .font(AppFonts.bodyMedium(16))
                                    .foregroundColor(AppColors.textPrimary)
                                Spacer()
                                Text(String(format: "%.1f/10", min(10, score)))
                                    .font(AppFonts.label(12))
                                    .foregroundColor(dim.color)
                                    .monospacedDigit()
                            }
                            Text(dim.summary)
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.textMuted)
                        }

                        if selectedDimension == dim {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(dim.color)
                        }
                    }
                    .padding(14)
                    .background(AppColors.card)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(selectedDimension == dim ? dim.color : AppColors.border, lineWidth: selectedDimension == dim ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
            }

            // Intention field
            if selectedDimension != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What's your intention?")
                        .font(AppFonts.heading(14))
                        .foregroundColor(AppColors.textSecondary)

                    TextField("e.g. Exercise 3x/week, read before bed...", text: $intention)
                        .font(AppFonts.body(15))
                        .padding(12)
                        .background(AppColors.surface)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                }

                Button {
                    guard let dim = selectedDimension else { return }
                    Haptics.success()
                    balanceManager.startSeasonGoal(dimension: dim, intention: intention)
                    withAnimation(.spring(response: 0.35)) {
                        showConfirmation = true
                    }
                } label: {
                    Text("Start 4-Week Focus")
                        .font(AppFonts.bodyMedium(16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(selectedDimension?.color ?? AppColors.accent)
                        .cornerRadius(16)
                }
            }
        }
    }

    private var confirmationView: some View {
        VStack(spacing: 16) {
            if let dim = selectedDimension {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(dim.color)

                Text("Season Goal Set!")
                    .font(AppFonts.heading(22))
                    .foregroundColor(AppColors.textPrimary)

                Text("Focus: \(dim.label) for 4 weeks")
                    .font(AppFonts.body(16))
                    .foregroundColor(AppColors.textSecondary)

                Text("Nudges will prioritize this dimension. Your Compass will track your progress.")
                    .font(AppFonts.caption(13))
                    .foregroundColor(AppColors.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

                Button {
                    dismiss()
                } label: {
                    Text("Let's Go")
                        .font(AppFonts.bodyMedium(16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(dim.color)
                        .cornerRadius(16)
                }
                .padding(.top, 12)
            }
        }
    }
}
