#if os(watchOS)
import SwiftUI
import WatchKit

/// Tab 1: Compass dashboard — glanceable in under 2 seconds.
///
/// Layout (top → bottom):
///   1. Hero Balance number (42pt bold) — single anchor metric
///   2. 2×2 dimension chip grid (Phy/Men/Emo/Spi) — numbers, not arcs
///   3. Status strip — tasks left · check-ins · streak
///   4. AI insight OR contextual prompt (early days)
///
/// Design rationale: concentric rings without numbers fail the glance test. A
/// ring at "7/10" looks identical to "5/10" at wrist distance. Outer rings also
/// visually dominate inner rings of the same value (circumference, not area,
/// drives perceived fill). Number-first chips are honest and take the same
/// vertical space.
struct WatchCompassView: View {
    var connectivity: WatchConnectivityManager

    private var data: WatchScheduleData? { connectivity.scheduleData }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                heroBalance
                dimensionGrid
                statusStrip
                aiInsightOrPrompt
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
        .containerBackground(for: .navigation) {
            timeOfDayGradient
        }
    }

    // MARK: - Hero Balance

    private var heroBalance: some View {
        let balance = averageScore
        let hasData = data?.bodyScore != nil

        return VStack(spacing: 0) {
            Text(hasData ? String(format: "%.1f", balance) : "—")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("BALANCE")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(1.2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            hasData
                ? "Balance score \(String(format: "%.1f", balance)) out of 10"
                : "No balance data yet"
        )
    }

    /// Average of the four dimension scores (0-10). Only counts populated
    /// values — a single nil won't skew the hero down to zero.
    private var averageScore: Double {
        let scores = [data?.bodyScore, data?.mindScore, data?.heartScore, data?.spiritScore]
            .compactMap { $0 }
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / Double(scores.count)
    }

    // MARK: - Dimension Grid (2×2)

    private var dimensionGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                dimensionChip(label: "Phy", value: data?.bodyScore, color: .green)
                dimensionChip(label: "Men", value: data?.mindScore, color: .blue)
            }
            HStack(spacing: 6) {
                dimensionChip(label: "Emo", value: data?.heartScore, color: .pink)
                dimensionChip(label: "Spi", value: data?.spiritScore, color: .purple)
            }
        }
    }

    private func dimensionChip(label: String, value: Double?, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))

            Spacer(minLength: 0)

            Text(value.map { String(format: "%.0f", $0) } ?? "—")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color.opacity(0.32), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(fullName(for: label)) \(value.map { String(format: "%.0f out of 10", $0) } ?? "no data")"
        )
    }

    private func fullName(for abbrev: String) -> String {
        switch abbrev {
        case "Phy": "Physical"
        case "Men": "Mental"
        case "Emo": "Emotional"
        case "Spi": "Spiritual"
        default: abbrev
        }
    }

    // MARK: - Status Strip

    private var statusStrip: some View {
        HStack(spacing: 10) {
            if let d = data {
                statusItem(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    text: "\(max(d.totalToday - d.completedToday, 0)) left"
                )

                if let completed = d.completedCheckIns {
                    statusItem(
                        icon: "sun.max.fill",
                        color: .yellow,
                        text: "\(completed.count)/4"
                    )
                }

                if d.streakDays > 0 {
                    statusItem(
                        icon: "flame.fill",
                        color: .orange,
                        text: "\(d.streakDays)d"
                    )
                }
            } else {
                Text("Syncing…")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func statusItem(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }

    // MARK: - AI Insight / Contextual Prompt

    @ViewBuilder
    private var aiInsightOrPrompt: some View {
        if let insight = data?.aiInsight, !insight.isEmpty {
            insightCard(text: insight)
        } else if data != nil {
            promptCard
        }
    }

    private func insightCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.yellow)
                Text("INSIGHT")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundColor(.yellow)
            }
            Text(text)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.yellow.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Insight: \(text)")
    }

    @ViewBuilder
    private var promptCard: some View {
        let totalToday = data?.totalToday ?? 0
        let remaining = totalToday - (data?.completedToday ?? 0)
        let completedSlots = data?.completedCheckIns?.count ?? 0
        let hasCheckIn = data?.nextCheckIn != nil

        VStack(alignment: .leading, spacing: 2) {
            if totalToday == 0 && remaining == 0 {
                promptRow(icon: "plus.circle", text: "Tap + to add your first task")
            } else if completedSlots < 4 && hasCheckIn {
                promptRow(icon: "arrow.right.circle", text: "Swipe → for check-in")
            } else {
                promptRow(icon: "chart.line.uptrend.xyaxis", text: "Your patterns are building…")
            }
        }
        .padding(.horizontal, 4)
    }

    private func promptRow(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
            Text(text)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    // MARK: - Background Gradient

    private var timeOfDayGradient: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let colors: [Color] = {
            switch hour {
            case 5..<8:   return [Color(red: 0.95, green: 0.6, blue: 0.3),  Color(red: 0.15, green: 0.1, blue: 0.2)]   // dawn
            case 8..<12:  return [Color(red: 0.2,  green: 0.35, blue: 0.5), Color(red: 0.08, green: 0.08, blue: 0.12)] // morning
            case 12..<17: return [Color(red: 0.15, green: 0.25, blue: 0.45), Color(red: 0.06, green: 0.06, blue: 0.1)]  // afternoon
            case 17..<20: return [Color(red: 0.6,  green: 0.3,  blue: 0.2), Color(red: 0.1,  green: 0.06, blue: 0.12)] // sunset
            default:      return [Color(red: 0.1,  green: 0.08, blue: 0.2), Color(red: 0.04, green: 0.04, blue: 0.08)] // night
            }
        }()
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}
#endif
