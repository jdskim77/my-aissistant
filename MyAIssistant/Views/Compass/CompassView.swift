import SwiftUI

/// Radar chart showing weekly balance across the four scored life dimensions.
/// Uses composite scores (0-10) from the 3-signal model: activity, satisfaction, consistency.
struct CompassView: View {
    let breakdowns: [LifeDimension: BalanceManager.DimensionBreakdown]
    let balanceScoreValue: Double
    let balanceStreak: Int

    var body: some View {
        VStack(spacing: 16) {
            // Header
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

                // Balance score badge
                HStack(spacing: 4) {
                    Text("Balance")
                        .font(AppFonts.label(11))
                        .foregroundColor(AppColors.textMuted)
                    Text(String(format: "%.1f", balanceScoreValue))
                        .font(AppFonts.heading(14))
                        .foregroundColor(balanceColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(balanceColor.opacity(0.1))
                .cornerRadius(8)
            }

            // Radar chart
            radarChart
                .frame(height: 200)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(radarAccessibilityLabel)

            // Dimension score cards
            dimensionCards

            // Balance streak
            if balanceStreak > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.gold)
                    Text("\(balanceStreak)-week balance streak")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textSecondary)
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

    // MARK: - Radar Chart

    private var radarChart: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 24
            let dims = LifeDimension.scored

            ZStack {
                // Background grid rings (at 2.5, 5, 7.5, 10)
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

                // Filled score area (normalized to 0-1 for chart: score/10)
                let scorePoints = dims.enumerated().map { index, dim -> CGPoint in
                    let value = (breakdowns[dim]?.composite ?? 0) / 10.0
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

                // Score dots + dimension icons
                ForEach(Array(dims.enumerated()), id: \.element.id) { index, dim in
                    let value = (breakdowns[dim]?.composite ?? 0) / 10.0
                    let angle = angleForIndex(index, total: dims.count)
                    let point = pointOnCircle(center: center, radius: radius * max(0.05, value), angle: angle)

                    Circle()
                        .fill(dim.color)
                        .frame(width: 8, height: 8)
                        .position(point)

                    let labelPoint = pointOnCircle(center: center, radius: radius + 16, angle: angle)
                    Image(systemName: dim.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(dim.color)
                        .position(labelPoint)
                }
            }
        }
    }

    // MARK: - Dimension Cards (replaces raw numbers)

    private var dimensionCards: some View {
        HStack(spacing: 8) {
            ForEach(LifeDimension.scored) { dim in
                let bd = breakdowns[dim] ?? BalanceManager.DimensionBreakdown(activity: 0, satisfaction: 5, consistency: 0)
                let score = bd.composite

                VStack(spacing: 6) {
                    // Score
                    Text(String(format: "%.1f", score))
                        .font(AppFonts.heading(16))
                        .foregroundColor(dim.color)
                        .monospacedDigit()

                    // Dimension name
                    Text(dim.label)
                        .font(AppFonts.caption(10))
                        .foregroundColor(AppColors.textMuted)

                    // 3-signal mini bars
                    VStack(spacing: 2) {
                        signalBar(value: bd.activity, max: 10, color: .green, label: "A")
                        signalBar(value: bd.satisfaction, max: 10, color: .blue, label: "S")
                        signalBar(value: bd.consistency, max: 10, color: .orange, label: "C")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(dim.color.opacity(0.06))
                .cornerRadius(10)
            }
        }
    }

    private func signalBar(value: Double, max: Double, color: Color, label: String) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(AppColors.textMuted)
                .frame(width: 8)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(AppColors.border.opacity(0.3))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(0.6))
                        .frame(width: geo.size.width * min(1, value / max))
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: - Accessibility

    private var radarAccessibilityLabel: String {
        let dims = LifeDimension.scored
        let descriptions = dims.map { dim in
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
        let fraction = Double(index) / Double(total)
        return fraction * 2 * .pi - .pi / 2
    }

    private func pointOnCircle(center: CGPoint, radius: Double, angle: Double) -> CGPoint {
        CGPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
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
