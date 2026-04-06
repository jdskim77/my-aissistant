import SwiftUI
import SwiftData

struct PatternsView: View {
    @Environment(\.patternEngine) private var patternEngine
    @Environment(\.subscriptionTier) private var tier
    @Query(sort: \TaskItem.date) private var allTasks: [TaskItem]
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var streak: Int { patternEngine?.currentStreak() ?? 0 }
    private var completionRate: Int { patternEngine?.completionRate() ?? 0 }
    private var avgTasksPerDay: Double { patternEngine?.averageTasksPerDay() ?? 0 }
    private var bestCheckIn: String { patternEngine?.bestCheckInTime() ?? "Morning" }
    private var weeklyDone: [Int] { patternEngine?.weeklyCompletions() ?? Array(repeating: 0, count: 7) }
    private var checkinHistory: [Bool] { patternEngine?.checkInConsistency() ?? Array(repeating: false, count: 7) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                Text("Patterns & Insights")
                    .font(AppFonts.display(28))
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.top, 8)

                // 4 key metrics
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    metricCard(title: "Current Streak", value: "\(streak)", unit: "days", icon: "flame.fill", color: AppColors.coral)
                    metricCard(title: "Completion Rate", value: "\(completionRate)", unit: "%", icon: "chart.line.uptrend.xyaxis", color: AppColors.accentWarm)
                    metricCard(title: "Avg Tasks/Day", value: String(format: "%.1f", avgTasksPerDay), unit: "", icon: "chart.bar.fill", color: AppColors.skyBlue)
                    metricCard(title: "Best Check-in", value: bestCheckIn, unit: "", icon: "clock.fill", color: AppColors.gold)
                }
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)

                // Weekly AI Review (Pro+ only shows generate button)
                WeeklyAIReviewView()
                    .offset(y: appeared ? 0 : 20)
                    .opacity(appeared ? 1 : 0)

                // Mood Trend Chart
                MoodTrendView()
                    .offset(y: appeared ? 0 : 20)
                    .opacity(appeared ? 1 : 0)

                // Weekly bar chart (extracted)
                WeeklyChartView(weeklyDone: weeklyDone)
                    .offset(y: appeared ? 0 : 20)
                    .opacity(appeared ? 1 : 0)

                // Check-in consistency
                consistencyGrid
                    .offset(y: appeared ? 0 : 20)
                    .opacity(appeared ? 1 : 0)

                // Activity tracker
                ActivityTimelineView()
                    .offset(y: appeared ? 0 : 20)
                    .opacity(appeared ? 1 : 0)

                // Category breakdown (extracted)
                CategoryBreakdownView(breakdown: patternEngine?.categoryBreakdown() ?? [])
                    .offset(y: appeared ? 0 : 20)
                    .opacity(appeared ? 1 : 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.6)) {
                appeared = true
            }
        }
    }

    // MARK: - Metric card

    private func metricCard(title: String, value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(AppFonts.heading(20))
                .foregroundColor(color)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(AppFonts.displayBold(32))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !unit.isEmpty {
                    Text(unit)
                        .font(AppFonts.bodyMedium(14))
                        .foregroundColor(color.opacity(0.7))
                }
            }

            Text(title)
                .font(AppFonts.caption(12))
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Consistency grid

    private var consistencyGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Check-in Consistency")
                .font(AppFonts.heading(16))
                .foregroundColor(AppColors.textPrimary)

            HStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(checkinHistory[i] ? AppColors.accentWarm : AppColors.border)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: checkinHistory[i] ? "checkmark" : "xmark")
                                    .font(AppFonts.label(13))
                                    .foregroundColor(checkinHistory[i] ? .white : AppColors.textMuted)
                            )

                        Text(dayLabels[i])
                            .font(AppFonts.caption(11))
                            .foregroundColor(AppColors.textMuted)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(dayLabels[i]), \(checkinHistory[i] ? "completed" : "missed")")
                }
            }
            .frame(maxWidth: .infinity)
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
