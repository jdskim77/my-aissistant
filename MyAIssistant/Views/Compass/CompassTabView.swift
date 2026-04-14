import SwiftUI

/// Full-screen Compass tab: radar chart, season goal, dimension breakdown,
/// and access to patterns, evening check-in, and weekly reflection.
struct CompassTabView: View {
    @Environment(\.balanceManager) private var balanceManager

    /// Single enum for sheet presentation — prevents multiple sheets conflicting.
    @State private var activeSheet: SheetType?
    @State private var showingInfo = false

    private enum SheetType: Identifiable {
        case eveningCheckIn, weeklyReflection, seasonGoal
        var id: Int { hashValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let bm = balanceManager {
                        compassContent(bm: bm)
                    } else {
                        // BUG-01 fix: show empty state when manager is nil
                        CompassEmptyView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Life Compass")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        showingInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(AppFonts.body(17))
                            .foregroundColor(AppColors.accent)
                    }
                    .accessibilityLabel("How Life Compass works")
                }
            }
            .sheet(isPresented: $showingInfo) {
                CompassInfoSheet()
            }
            // Single .sheet on stable parent — fixes BUG-02
            .sheet(item: $activeSheet) { sheet in
                if let bm = balanceManager {
                    switch sheet {
                    case .eveningCheckIn:
                        EveningCheckInView(balanceManager: bm)
                    case .weeklyReflection:
                        WeeklyReflectionView(balanceManager: bm)
                    case .seasonGoal:
                        SeasonGoalView(balanceManager: bm)
                    }
                }
            }
        }
    }

    // MARK: - Content

    private func compassContent(bm: BalanceManager) -> some View {
        let breakdowns = bm.weeklyBreakdowns()
        let hasData = bm.hasRealData()

        return Group {
            if hasData {
                VStack(spacing: 20) {
                    CompassView(
                        breakdowns: breakdowns,
                        balanceScoreValue: bm.balanceScore(),
                        balanceStreak: bm.balanceStreak(),
                        hasRealData: hasData
                    )

                    if let goal = bm.activeSeasonGoal() {
                        seasonGoalCard(goal, bm: bm)
                    } else {
                        newSeasonGoalPrompt
                    }

                    dimensionBreakdown(breakdowns: breakdowns, bm: bm)

                    // Energy insights (Phase 3 — shows after 3+ weeks of data)
                    if let insight = bm.energyInsights() {
                        energyInsightCard(insight: insight, bm: bm)
                    }

                    actionsSection(bm: bm)
                }
            } else {
                VStack(spacing: 20) {
                    CompassEmptyView()
                    actionsSection(bm: bm)
                }
            }
        }
    }

    // MARK: - Season Goal Card (BUG-04 fix: Button instead of onTapGesture)

    private func seasonGoalCard(_ goal: SeasonGoal, bm: BalanceManager) -> some View {
        Button {
            Haptics.light()
            activeSheet = .seasonGoal
        } label: {
            HStack(spacing: 10) {
                Image(systemName: goal.dimension.icon)
                    .font(AppFonts.heading(18).weight(.medium))
                    .foregroundColor(goal.dimension.color)
                    .frame(width: 36, height: 36)
                    .background(goal.dimension.color.opacity(0.1))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Season Goal: \(goal.dimension.label)")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textPrimary)

                    if !goal.intention.isEmpty {
                        Text(goal.intention)
                            .font(AppFonts.caption(13))
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                VStack(spacing: 2) {
                    ZStack {
                        Circle()
                            .stroke(AppColors.border, lineWidth: 3)
                            .frame(width: 36, height: 36)
                        Circle()
                            .trim(from: 0, to: goal.progress)
                            .stroke(goal.dimension.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 36, height: 36)
                            .rotationEffect(.degrees(-90))
                        Text("\(max(0, min(100, Int(goal.progress * 100))))%")
                            .font(AppFonts.caption(11))
                            .foregroundColor(AppColors.textSecondary)
                    }
                    Text("\(goal.daysRemaining)d left")
                        .font(AppFonts.caption(11))
                        .foregroundColor(AppColors.textMuted)
                }

                // Trailing chevron — the universal "this card opens detail"
                // signal. Without this, the card was visually identical to a
                // static info card and users had no cue it was tappable.
                Image(systemName: "chevron.right")
                    .font(AppFonts.label(13))
                    .foregroundColor(AppColors.textMuted)
            }
            .padding(16)
            .background(AppColors.card)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(goal.dimension.color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.scale)
        .accessibilityLabel("Season Goal: \(goal.dimension.label), \(goal.daysRemaining) days left")
        .accessibilityHint("Opens season goal detail")
    }

    private var newSeasonGoalPrompt: some View {
        Button {
            Haptics.light()
            activeSheet = .seasonGoal
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "target")
                    .font(AppFonts.heading(18))
                    .foregroundColor(AppColors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set a Season Goal")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textPrimary)
                    Text("Focus on one dimension for 4 weeks")
                        .font(AppFonts.caption(13))
                        .foregroundColor(AppColors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFonts.label(13))
                    .foregroundColor(AppColors.textMuted)
            }
            .padding(16)
            .background(AppColors.card)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.scale)
        .accessibilityLabel("Set a Season Goal")
    }

    // MARK: - Dimension Breakdown (BUG-16 fix: clamped score)

    private func dimensionBreakdown(breakdowns: [LifeDimension: BalanceManager.DimensionBreakdown], bm: BalanceManager) -> some View {
        let counts = bm.thisWeekTaskCounts()

        return VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(AppFonts.heading(15))
                .foregroundColor(AppColors.textPrimary)

            ForEach(LifeDimension.scored) { dim in
                let score = breakdowns[dim]?.composite ?? 0
                let clampedScore = max(0.0, min(10.0, score))
                let displayScore = String(format: "%.1f", clampedScore)
                let count = counts[dim] ?? 0

                HStack(spacing: 12) {
                    Image(systemName: dim.icon)
                        .font(AppFonts.body(16).weight(.medium))
                        .foregroundColor(dim.color)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(dim.label)
                                .font(AppFonts.bodyMedium(14))
                                .foregroundColor(AppColors.textPrimary)
                            Spacer()
                            Text("\(displayScore)/10")
                                .font(AppFonts.heading(14))
                                .foregroundColor(dim.color)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(AppColors.border)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(dim.color)
                                    .frame(width: geo.size.width * (clampedScore / 10.0), height: 6)
                            }
                        }
                        .frame(height: 6)

                        Text("\(count) task\(count == 1 ? "" : "s") completed")
                            .font(AppFonts.caption(11))
                            .foregroundColor(AppColors.textMuted)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(dim.label): \(displayScore) out of 10, \(count) tasks completed")
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

    // MARK: - Actions (BUG-15 fix: padding 16 for 44pt targets)

    // MARK: - Energy Insight Card

    private func energyInsightCard(insight: String, bm: BalanceManager) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.heart.fill")
                    .font(AppFonts.label(14))
                    .foregroundColor(AppColors.gold)
                Text("Energy Insight")
                    .font(AppFonts.heading(14))
                    .foregroundColor(AppColors.textPrimary)
            }

            Text(insight)
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textSecondary)

            // Mini trend
            let trends = bm.energyTrend()
            if trends.count >= 2 {
                HStack(spacing: 4) {
                    ForEach(trends.reversed(), id: \.weekOffset) { week in
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(week.average >= 0 ? AppColors.completionGreen : AppColors.coral)
                                .frame(width: 16, height: max(4, CGFloat(abs(week.average) + 1) * 8))
                            Text("W\(week.weekOffset)")
                                .font(AppFonts.caption(9))
                                .foregroundColor(AppColors.textMuted)
                        }
                    }
                    Spacer()
                }
                .frame(height: 40)
            }
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.gold.opacity(0.2), lineWidth: 1)
        )
    }

    /// Current time-appropriate check-in slot
    private var currentCheckInSlot: CheckInTime {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return .morning }
        if hour < 17 { return .midday }
        if hour < 21 { return .afternoon }
        return .night
    }

    private func actionsSection(bm: BalanceManager) -> some View {
        VStack(spacing: 10) {
            if !bm.hasCheckedInToday() {
                Button {
                    Haptics.light()
                    activeSheet = .eveningCheckIn
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: currentCheckInSlot.sfSymbol)
                            .foregroundColor(currentCheckInSlot.color)
                        Text("\(currentCheckInSlot.rawValue) Check-In")
                            .font(AppFonts.bodyMedium(15))
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(AppFonts.label(13))
                            .foregroundColor(AppColors.textMuted)
                    }
                    .padding(16)
                    .background(AppColors.card)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.scale)
                .accessibilityLabel("\(currentCheckInSlot.rawValue) Check-In")
            }

            NavigationLink {
                PatternsView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(AppColors.accent)
                    Text("Detailed Patterns")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFonts.label(13))
                        .foregroundColor(AppColors.textMuted)
                }
                .padding(16)
                .background(AppColors.card)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.scale)
            .accessibilityLabel("View Detailed Patterns")
        }
    }
}
