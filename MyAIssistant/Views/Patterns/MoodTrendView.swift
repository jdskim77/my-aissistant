import SwiftUI
import Charts

struct MoodDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let mood: Double
    let completionRate: Double
}

struct MoodTrendView: View {
    @Environment(\.patternEngine) private var patternEngine

    private var dataPoints: [MoodDataPoint] {
        patternEngine?.moodTrend(days: 14) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mood & Productivity")
                .font(AppFonts.heading(16))
                .foregroundColor(AppColors.textPrimary)

            if dataPoints.isEmpty {
                emptyState
            } else {
                chart
                legend
                correlation
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

    private var chart: some View {
        Chart {
            ForEach(dataPoints) { point in
                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Mood", point.mood)
                )
                .foregroundStyle(AppColors.coral)
                .symbol(Circle())
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Mood", point.mood)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.coral.opacity(0.2), AppColors.coral.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Completion", point.completionRate * 5)
                )
                .foregroundStyle(AppColors.accent)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                .symbol(Diamond())
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: 0...5)
        .chartYAxis {
            AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let intVal = value.as(Int.self) {
                        Text("\(intVal)")
                            .font(AppFonts.caption(11))
                            .foregroundColor(AppColors.textMuted)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: 180)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Circle()
                    .fill(AppColors.coral)
                    .frame(width: 8, height: 8)
                Text("Mood (1-5)")
                    .font(AppFonts.caption(11))
                    .foregroundColor(AppColors.textMuted)
            }

            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(AppColors.accent)
                    .frame(width: 12, height: 2)
                Text("Completion %")
                    .font(AppFonts.caption(11))
                    .foregroundColor(AppColors.textMuted)
            }
        }
    }

    private var correlation: some View {
        Group {
            if let corr = patternEngine?.moodProductivityCorrelation() {
                HStack(spacing: 6) {
                    Image(systemName: correlationIcon(corr))
                        .font(AppFonts.caption(13))
                        .foregroundColor(correlationColor(corr))

                    Text(correlationText(corr))
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(.top, 4)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(AppFonts.icon(24))
                .foregroundColor(AppColors.skyBlue)

            Text("Complete check-ins with mood ratings to see trends")
                .font(AppFonts.caption(12))
                .foregroundColor(AppColors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func correlationIcon(_ value: Double) -> String {
        if value > 0.3 { return "arrow.up.right" }
        if value < -0.3 { return "arrow.down.right" }
        return "arrow.right"
    }

    private func correlationColor(_ value: Double) -> Color {
        if value > 0.3 { return AppColors.accentWarm }
        if value < -0.3 { return AppColors.coral }
        return AppColors.textMuted
    }

    private func correlationText(_ value: Double) -> String {
        if value > 0.5 {
            return "Strong link: higher mood = more tasks done"
        } else if value > 0.3 {
            return "Moderate link between mood and productivity"
        } else if value < -0.3 {
            return "You tend to get more done on lower-mood days"
        } else {
            return "Mood and productivity appear independent"
        }
    }
}

struct Diamond: ChartSymbolShape {
    var perceptualUnitRect: CGRect { CGRect(x: 0, y: 0, width: 1, height: 1) }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let size = min(rect.width, rect.height) / 2
        path.move(to: CGPoint(x: center.x, y: center.y - size))
        path.addLine(to: CGPoint(x: center.x + size, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + size))
        path.addLine(to: CGPoint(x: center.x - size, y: center.y))
        path.closeSubpath()
        return path
    }
}
