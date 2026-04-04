import SwiftUI

/// Radar chart showing weekly balance across the four scored life dimensions.
/// Tappable dimension cards open a detail sheet. First-visit shows coach marks.
struct CompassView: View {
    let breakdowns: [LifeDimension: BalanceManager.DimensionBreakdown]
    let balanceScoreValue: Double
    let balanceStreak: Int
    let hasRealData: Bool

    @State private var selectedDimension: LifeDimension?
    @State private var showCoachMarks = false

    /// Track whether user has seen the explainer
    @AppStorage("compassCoachMarksSeen") private var coachMarksSeen = false

    var body: some View {
        VStack(spacing: 16) {
            // Header with info button
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "safari")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                    Text("Life Compass")
                        .font(AppFonts.heading(16))
                        .foregroundColor(AppColors.textPrimary)
                }

                Spacer()

                // Info button — always accessible
                Button {
                    Haptics.light()
                    showCoachMarks = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16))
                        .foregroundColor(AppColors.textMuted)
                }
                .accessibilityLabel("How Life Compass works")

                // Balance score badge
                HStack(spacing: 4) {
                    Text("Balance")
                        .font(AppFonts.label(11))
                        .foregroundColor(AppColors.textMuted)
                    Text(String(format: "%.1f", balanceScoreValue))
                        .font(AppFonts.heading(14))
                        .foregroundColor(balanceColor)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(balanceColor.opacity(0.1))
                .cornerRadius(8)
            }

            // Radar chart with axis labels
            radarChart
                .frame(height: 200)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(radarAccessibilityLabel)

            // Tappable dimension cards (simplified — no A/S/C bars)
            dimensionCards

            // Balance streak (only with real data)
            if hasRealData && balanceStreak > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.gold)
                    Text("\(balanceStreak)-week balance streak")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            // Hint for new users
            if !hasRealData {
                Text("Complete tasks and do check-ins to see your scores change")
                    .font(AppFonts.caption(11))
                    .foregroundColor(AppColors.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .onAppear {
            if !coachMarksSeen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showCoachMarks = true
                    coachMarksSeen = true
                }
            }
        }
        .sheet(item: $selectedDimension) { dim in
            DimensionDetailSheet(
                dimension: dim,
                breakdown: breakdowns[dim] ?? BalanceManager.DimensionBreakdown(activity: 5, satisfaction: 5, consistency: 5)
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showCoachMarks) {
            CompassCoachMarks()
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Radar Chart (with axis labels)

    private var radarChart: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 32
            let dims = LifeDimension.scored

            ZStack {
                // Background grid rings
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                    radarPolygon(sides: dims.count, radius: radius * level, center: center)
                        .stroke(AppColors.border.opacity(0.4), lineWidth: 0.5)
                }

                // Axis lines
                ForEach(Array(dims.enumerated()), id: \.element.id) { index, _ in
                    let angle = angleForIndex(index, total: dims.count)
                    let point = pointOnCircle(center: center, radius: radius, angle: angle)
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: point)
                    }
                    .stroke(AppColors.border.opacity(0.3), lineWidth: 0.5)
                }

                // Filled score area
                let scorePoints = dims.enumerated().map { index, dim -> CGPoint in
                    let value = (breakdowns[dim]?.composite ?? 5) / 10.0
                    let angle = angleForIndex(index, total: dims.count)
                    return pointOnCircle(center: center, radius: radius * max(0.05, value), angle: angle)
                }

                Path { path in
                    guard let first = scorePoints.first else { return }
                    path.move(to: first)
                    for point in scorePoints.dropFirst() { path.addLine(to: point) }
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [AppColors.accent.opacity(0.2), AppColors.accent.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { path in
                    guard let first = scorePoints.first else { return }
                    path.move(to: first)
                    for point in scorePoints.dropFirst() { path.addLine(to: point) }
                    path.closeSubpath()
                }
                .stroke(AppColors.accent, lineWidth: 2)

                // Score dots + dimension LABELS (icon + name)
                ForEach(Array(dims.enumerated()), id: \.element.id) { index, dim in
                    let value = (breakdowns[dim]?.composite ?? 5) / 10.0
                    let angle = angleForIndex(index, total: dims.count)
                    let point = pointOnCircle(center: center, radius: radius * max(0.05, value), angle: angle)

                    Circle()
                        .fill(dim.color)
                        .frame(width: 8, height: 8)
                        .position(point)

                    // Axis label: icon + short name
                    let labelPoint = pointOnCircle(center: center, radius: radius + 22, angle: angle)
                    VStack(spacing: 1) {
                        Image(systemName: dim.icon)
                            .font(.system(size: 12, weight: .medium))
                        Text(dim.label.prefix(4))
                            .font(AppFonts.caption(8))
                    }
                    .foregroundColor(dim.color)
                    .position(labelPoint)
                }
            }
        }
    }

    // MARK: - Dimension Cards (simplified + tappable)

    private var dimensionCards: some View {
        HStack(spacing: 8) {
            ForEach(LifeDimension.scored) { dim in
                let bd = breakdowns[dim] ?? BalanceManager.DimensionBreakdown(activity: 5, satisfaction: 5, consistency: 5)
                let score = bd.composite

                Button {
                    Haptics.light()
                    selectedDimension = dim
                } label: {
                    VStack(spacing: 6) {
                        Text(String(format: "%.1f", min(10, score)))
                            .font(AppFonts.heading(18))
                            .foregroundColor(dim.color)
                            .monospacedDigit()

                        Text(dim.label)
                            .font(AppFonts.caption(10))
                            .foregroundColor(AppColors.textMuted)

                        // Simple score ring instead of A/S/C bars
                        ZStack {
                            Circle()
                                .stroke(dim.color.opacity(0.15), lineWidth: 3)
                                .frame(width: 24, height: 24)
                            Circle()
                                .trim(from: 0, to: min(1, score / 10))
                                .stroke(dim.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 24, height: 24)
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(dim.color.opacity(0.06))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(dim.color.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(dim.label), score \(String(format: "%.1f", score)) out of 10. Tap for details.")
            }
        }
    }

    // MARK: - Accessibility

    private var radarAccessibilityLabel: String {
        let descriptions = LifeDimension.scored.map { dim in
            let score = String(format: "%.1f", breakdowns[dim]?.composite ?? 0)
            return "\(dim.label) \(score) out of 10"
        }
        return "Life Compass radar chart. " + descriptions.joined(separator: ", ") + ". Balance score \(String(format: "%.1f", balanceScoreValue)) out of 10."
    }

    // MARK: - Helpers

    private var balanceColor: Color {
        if balanceScoreValue >= 7 { return AppColors.completionGreen }
        if balanceScoreValue >= 4 { return AppColors.gold }
        return AppColors.coral
    }

    private func angleForIndex(_ index: Int, total: Int) -> Double {
        Double(index) / Double(total) * 2 * .pi - .pi / 2
    }

    private func pointOnCircle(center: CGPoint, radius: Double, angle: Double) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    private func radarPolygon(sides: Int, radius: Double, center: CGPoint) -> Path {
        Path { path in
            for i in 0..<sides {
                let angle = angleForIndex(i, total: sides)
                let point = pointOnCircle(center: center, radius: radius, angle: angle)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }
}

// MARK: - Dimension Detail Sheet (shown on card tap)

struct DimensionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let dimension: LifeDimension
    let breakdown: BalanceManager.DimensionBreakdown

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: dimension.icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(dimension.color)
                        .frame(width: 48, height: 48)
                        .background(dimension.color.opacity(0.1))
                        .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(dimension.label)
                            .font(AppFonts.heading(20))
                            .foregroundColor(AppColors.textPrimary)
                        Text(dimension.summary)
                            .font(AppFonts.caption(12))
                            .foregroundColor(AppColors.textMuted)
                    }
                    Spacer()

                    Text(String(format: "%.1f", min(10, breakdown.composite)))
                        .font(AppFonts.display(28))
                        .foregroundColor(dimension.color)
                        .monospacedDigit()
                }

                Divider()

                // 3-Signal Breakdown
                VStack(spacing: 16) {
                    Text("Score Breakdown")
                        .font(AppFonts.heading(15))
                        .foregroundColor(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    signalDetail(
                        icon: "flame",
                        name: "Activity",
                        description: "Effort-weighted tasks completed this week",
                        value: breakdown.activity,
                        weight: "30%",
                        color: .green
                    )

                    signalDetail(
                        icon: "heart.fill",
                        name: "Satisfaction",
                        description: "Your self-rated well-being from check-ins",
                        value: breakdown.satisfaction,
                        weight: "40%",
                        color: .blue
                    )

                    signalDetail(
                        icon: "calendar",
                        name: "Consistency",
                        description: "How many days this week you were active",
                        value: breakdown.consistency,
                        weight: "30%",
                        color: .orange
                    )
                }

                Spacer()
            }
            .padding(20)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("\(dimension.label) Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func signalDetail(icon: String, name: String, description: String, value: Double, weight: String, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(name)
                            .font(AppFonts.bodyMedium(14))
                            .foregroundColor(AppColors.textPrimary)
                        Text("(\(weight))")
                            .font(AppFonts.caption(11))
                            .foregroundColor(AppColors.textMuted)
                    }
                    Text(description)
                        .font(AppFonts.caption(11))
                        .foregroundColor(AppColors.textMuted)
                }
                Spacer()
                Text(String(format: "%.1f", min(10, value)))
                    .font(AppFonts.heading(16))
                    .foregroundColor(color)
                    .monospacedDigit()
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppColors.border.opacity(0.3))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.6))
                        .frame(width: geo.size.width * min(1, value / 10))
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(AppColors.surface)
        .cornerRadius(12)
    }
}

// MARK: - Coach Marks (First-Visit Explainer)

struct CompassCoachMarks: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0

    private let steps: [(icon: String, title: String, body: String)] = [
        (
            "safari",
            "Your Life Compass",
            "The compass tracks your weekly balance across four areas of life: Physical, Mental, Emotional, and Spiritual. The goal isn't to max everything out — it's to find balance."
        ),
        (
            "chart.bar.fill",
            "Three Signals, One Score",
            "Each dimension is scored from 0 to 10 using three signals:\n\n🔥 Activity — effort from completed tasks\n💙 Satisfaction — how you rate yourself in check-ins\n📅 Consistency — how many days you're active\n\nSatisfaction counts the most (40%) because how you feel matters more than how much you do."
        ),
        (
            "scale.3d",
            "Balance Over Perfection",
            "The Balance Score rewards even-ness. All 5s scores higher than one 10 and three 1s. A round wheel rolls better than a jagged one.\n\nTap any dimension card to see the full breakdown."
        )
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Step indicator
            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Circle()
                        .fill(i == currentStep ? AppColors.accent : AppColors.border)
                        .frame(width: 6, height: 6)
                }
            }

            // Content
            let step = steps[currentStep]

            VStack(spacing: 16) {
                Image(systemName: step.icon)
                    .font(.system(size: 40))
                    .foregroundColor(AppColors.accent)

                Text(step.title)
                    .font(AppFonts.heading(20))
                    .foregroundColor(AppColors.textPrimary)

                Text(step.body)
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 24)

            Spacer()

            // Navigation buttons
            HStack(spacing: 12) {
                if currentStep > 0 {
                    Button {
                        Haptics.light()
                        withAnimation(.snappy(duration: 0.25)) { currentStep -= 1 }
                    } label: {
                        Text("Back")
                            .font(AppFonts.bodyMedium(15))
                            .foregroundColor(AppColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppColors.surface)
                            .cornerRadius(12)
                    }
                }

                Button {
                    Haptics.light()
                    if currentStep < steps.count - 1 {
                        withAnimation(.snappy(duration: 0.25)) { currentStep += 1 }
                    } else {
                        dismiss()
                    }
                } label: {
                    Text(currentStep < steps.count - 1 ? "Next" : "Got It")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.accent)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(AppColors.background.ignoresSafeArea())
    }
}

// MARK: - Empty State

struct CompassEmptyView: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "safari")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.accent)
                Text("Life Compass")
                    .font(AppFonts.heading(16))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
            }

            VStack(spacing: 8) {
                Image(systemName: "safari")
                    .font(.system(size: 32))
                    .foregroundColor(AppColors.textMuted)

                Text("Your Compass builds as you tag tasks")
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                Text("Complete tasks tagged with life dimensions and rate your satisfaction during check-ins to see your weekly balance here.")
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 24)
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
}
