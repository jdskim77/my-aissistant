import SwiftUI

struct OnboardingCompassRevealView: View {
    let ratings: [LifeDimension: Int]
    let onContinue: () -> Void
    @State private var revealed = false
    @State private var appeared = false

    private var weakest: LifeDimension {
        StarterTaskPool.weakestDimension(from: ratings)
    }

    private var weakestLabel: String {
        switch weakest {
        case .physical:  return "your body"
        case .mental:    return "your mind"
        case .emotional: return "your connections"
        case .spiritual: return "your contribution"
        case .practical: return "your routines"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text("Here's Your Starting Point")
                            .font(AppFonts.display(24))
                            .foregroundColor(AppColors.textPrimary)

                        Text("A balanced shape means a balanced life")
                            .font(AppFonts.body(14))
                            .foregroundColor(AppColors.textMuted)
                    }
                    .opacity(appeared ? 1 : 0)
                    .padding(.top, 20)

                    // Radar chart
                    radarChart
                        .frame(height: 240)
                        .padding(.horizontal, 16)
                        .scaleEffect(revealed ? 1 : 0.3)
                        .opacity(revealed ? 1 : 0)

                    // Dimension score cards
                    VStack(spacing: 10) {
                        ForEach(LifeDimension.scored) { dim in
                            let score = ratings[dim] ?? 5
                            dimensionScoreRow(dim: dim, score: score)
                        }
                    }
                    .padding(.horizontal, 20)
                    .opacity(appeared ? 1 : 0)

                    // Callout for weakest
                    HStack(spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .font(AppFonts.body(16))
                            .foregroundColor(AppColors.gold)
                        Text("Looks like **\(weakestLabel)** could use some attention. Let's start there.")
                            .font(AppFonts.body(14))
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(AppColors.gold.opacity(0.08))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .opacity(appeared ? 1 : 0)
                }
                .padding(.bottom, 100)
            }

            // Continue button
            VStack(spacing: 0) {
                Divider()
                Button(action: onContinue) {
                    Text("What Can I Do?")
                        .font(AppFonts.bodyMedium(17))
                        .foregroundColor(AppColors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.accent)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .background(AppColors.surface)
            .opacity(appeared ? 1 : 0)
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                appeared = true
            }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.3)) {
                revealed = true
            }
        }
    }

    // MARK: - Dimension Score Row

    private func dimensionScoreRow(dim: LifeDimension, score: Int) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: dim.icon)
                .font(AppFonts.body(16))
                .foregroundColor(dim.color)
                .frame(width: 36, height: 36)
                .background(dim.color.opacity(0.1))
                .cornerRadius(8)

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(dim.label)
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(AppColors.textPrimary)
                Text(scoreLabel(score))
                    .font(AppFonts.caption(12))
                    .foregroundColor(scoreColor(score))
            }

            Spacer()

            // Score with progress bar
            HStack(spacing: 10) {
                // Mini progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(AppColors.border.opacity(0.3))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(scoreColor(score))
                            .frame(width: geo.size.width * Double(score) / 10.0)
                    }
                }
                .frame(width: 60, height: 6)

                // Score number
                Text("\(score)")
                    .font(AppFonts.heading(18))
                    .foregroundColor(scoreColor(score))
                    .monospacedDigit()
                    .frame(width: 28, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppColors.card)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Score Helpers

    private func scoreLabel(_ score: Int) -> String {
        switch score {
        case 9: return "Thriving"
        case 7: return "Good"
        case 5: return "Okay"
        case 3: return "Needs attention"
        case 1: return "Struggling"
        default: return "Okay"
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 7...10: return AppColors.completionGreen
        case 5...6:  return AppColors.gold
        case 3...4:  return AppColors.accentWarm
        default:     return AppColors.coral
        }
    }

    // MARK: - Radar Chart

    private var radarChart: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 36
            let dims = LifeDimension.scored

            ZStack {
                // Outer "target" ring — shows what 10/10 looks like
                radarPolygon(sides: dims.count, radius: radius, center: center)
                    .stroke(AppColors.accent.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                // Inner grid rings (lighter)
                ForEach([0.25, 0.5, 0.75], id: \.self) { level in
                    radarPolygon(sides: dims.count, radius: radius * level, center: center)
                        .stroke(AppColors.border.opacity(0.25), lineWidth: 0.5)
                }

                // Axis lines
                ForEach(Array(dims.enumerated()), id: \.element.id) { index, _ in
                    let angle = angleForIndex(index, total: dims.count)
                    let point = pointOnCircle(center: center, radius: radius, angle: angle)
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: point)
                    }
                    .stroke(AppColors.border.opacity(0.2), lineWidth: 0.5)
                }

                if revealed {
                    // Filled score area
                    let scorePoints = dims.enumerated().map { index, dim -> CGPoint in
                        let value = Double(ratings[dim] ?? 5) / 10.0
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
                            colors: [AppColors.accent.opacity(0.25), AppColors.accent.opacity(0.08)],
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

                    // Score dots (colored per dimension)
                    ForEach(Array(dims.enumerated()), id: \.element.id) { index, dim in
                        let value = Double(ratings[dim] ?? 5) / 10.0
                        let angle = angleForIndex(index, total: dims.count)
                        let point = pointOnCircle(center: center, radius: radius * max(0.05, value), angle: angle)

                        Circle()
                            .fill(dim.color)
                            .frame(width: 10, height: 10)
                            .shadow(color: dim.color.opacity(0.3), radius: 3)
                            .position(point)
                    }
                }

                // Axis labels — FULL dimension names
                ForEach(Array(dims.enumerated()), id: \.element.id) { index, dim in
                    let angle = angleForIndex(index, total: dims.count)
                    let labelPoint = pointOnCircle(center: center, radius: radius + 26, angle: angle)
                    VStack(spacing: 2) {
                        Image(systemName: dim.icon)
                            .font(AppFonts.label(13))
                        Text(dim.label)
                            .font(AppFonts.caption(10))
                            .fontWeight(.medium)
                    }
                    .foregroundColor(dim.color)
                    .position(labelPoint)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let descriptions = LifeDimension.scored.map { dim in
            "\(dim.label) \(ratings[dim] ?? 5) out of 10, \(scoreLabel(ratings[dim] ?? 5))"
        }
        return "Your Life Compass. " + descriptions.joined(separator: ". ") + ". The goal is a balanced, round shape."
    }

    // MARK: - Geometry Helpers

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
