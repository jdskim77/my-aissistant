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
                VStack(spacing: 24) {
                    if let goal = existingGoal {
                        activeGoalCard(goal)
                    } else {
                        newGoalFlow
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
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

    // MARK: - Active Goal Card

    private func activeGoalCard(_ goal: SeasonGoal) -> some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: goal.dimension.icon)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(goal.dimension.color)

                Text(goal.dimension.label)
                    .font(AppFonts.heading(22))
                    .foregroundColor(AppColors.textPrimary)

                if !goal.intention.isEmpty {
                    Text(goal.intention)
                        .font(AppFonts.body(15))
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Progress ring
            ZStack {
                Circle()
                    .stroke(AppColors.border, lineWidth: 8)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: goal.progress)
                    .stroke(goal.dimension.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(goal.daysRemaining)")
                        .font(AppFonts.heading(24))
                        .foregroundColor(AppColors.textPrimary)
                    Text("days left")
                        .font(AppFonts.caption(11))
                        .foregroundColor(AppColors.textMuted)
                }
            }

            // This week's score for the goal dimension
            if let score = balanceManager.seasonGoalProgress() {
                let displayScore = String(format: "%.1f", min(10, score))
                HStack(spacing: 8) {
                    Text("This week's \(goal.dimension.label) score:")
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.textSecondary)
                    Text("\(displayScore)/10")
                        .font(AppFonts.heading(16))
                        .foregroundColor(goal.dimension.color)
                        .monospacedDigit()
                }
                .padding(12)
                .background(goal.dimension.color.opacity(0.08))
                .cornerRadius(12)
            }

            // Complete early button (BUG-26: requires confirmation)
            Button {
                Haptics.light()
                showEndGoalConfirmation = true
            } label: {
                Text("End Goal Early")
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textMuted)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("End season goal early")
        }
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

            // Dimension cards
            ForEach(LifeDimension.scored) { dim in
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
                            Text(dim.label)
                                .font(AppFonts.bodyMedium(16))
                                .foregroundColor(AppColors.textPrimary)
                            Text(dim.summary)
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.textMuted)
                        }

                        Spacer()

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
