import SwiftUI

struct WeeklyChartView: View {
    let weeklyDone: [Int]
    private let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let maxVal = max(weeklyDone.max() ?? 1, 1)

        VStack(alignment: .leading, spacing: 14) {
            Text("Weekly Completions")
                .font(AppFonts.heading(16))
                .foregroundColor(AppColors.textPrimary)

            HStack(alignment: .bottom, spacing: 12) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 6) {
                        Text("\(weeklyDone[i])")
                            .font(AppFonts.caption(11))
                            .foregroundColor(AppColors.textMuted)

                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [AppColors.accentWarm, AppColors.accent],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: CGFloat(weeklyDone[i]) / CGFloat(maxVal) * 100)

                        Text(dayLabels[i])
                            .font(AppFonts.caption(11))
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 140)
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
        )
    }
}
