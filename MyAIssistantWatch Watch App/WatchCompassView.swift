#if os(watchOS)
import SwiftUI
import WatchKit

/// Tab 1: The compass dashboard — 4-dimension rings, greeting, streak, AI insight.
struct WatchCompassView: View {
    var connectivity: WatchConnectivityManager

    private var data: WatchScheduleData? { connectivity.scheduleData }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                greetingText
                compassRings
                dimensionLegend
                statsRow
                aiInsightCard
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .containerBackground(for: .navigation) {
            timeOfDayGradient
        }
    }

    // MARK: - Greeting

    private var greetingText: some View {
        let name = data?.userName ?? ""
        let greeting = timeOfDayGreeting
        let display = name.isEmpty ? greeting : "\(greeting), \(name)"

        return Text(display)
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    private var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Winding down"
        }
    }

    // MARK: - Compass Rings

    private var compassRings: some View {
        let body = data?.bodyScore ?? 0
        let mind = data?.mindScore ?? 0
        let heart = data?.heartScore ?? 0
        let spirit = data?.spiritScore ?? 0
        let hasData = data?.bodyScore != nil || data?.mindScore != nil ||
                      data?.heartScore != nil || data?.spiritScore != nil

        return ZStack {
            // Ring backgrounds (gray tracks)
            dimensionRing(progress: 1.0, color: .gray.opacity(0.2), size: 110, width: 7)
            dimensionRing(progress: 1.0, color: .gray.opacity(0.2), size: 88, width: 7)
            dimensionRing(progress: 1.0, color: .gray.opacity(0.2), size: 66, width: 7)
            dimensionRing(progress: 1.0, color: .gray.opacity(0.2), size: 44, width: 7)

            // Filled rings (outer to inner: Body, Mind, Heart, Spirit)
            dimensionRing(progress: body / 10.0, color: .green, size: 110, width: 7)
            dimensionRing(progress: mind / 10.0, color: .blue, size: 88, width: 7)
            dimensionRing(progress: heart / 10.0, color: .pink, size: 66, width: 7)
            dimensionRing(progress: spirit / 10.0, color: .purple, size: 44, width: 7)

            // Center content
            if !hasData {
                Image(systemName: "circle.dotted")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 120)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(compassAccessibilityLabel)
    }

    private func dimensionRing(progress: Double, color: Color, size: CGFloat, width: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: min(max(progress, 0), 1.0))
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(-90))
    }

    private var compassAccessibilityLabel: String {
        guard let d = data else { return "Compass: no data yet" }
        let body = d.bodyScore.map { String(format: "%.0f", $0) } ?? "no data"
        let mind = d.mindScore.map { String(format: "%.0f", $0) } ?? "no data"
        let heart = d.heartScore.map { String(format: "%.0f", $0) } ?? "no data"
        let spirit = d.spiritScore.map { String(format: "%.0f", $0) } ?? "no data"
        return "Compass: Body \(body), Mind \(mind), Heart \(heart), Spirit \(spirit) out of 10"
    }

    // MARK: - Dimension Legend

    private var dimensionLegend: some View {
        HStack(spacing: 8) {
            legendDot("B", color: .green)
            legendDot("M", color: .blue)
            legendDot("H", color: .pink)
            legendDot("S", color: .purple)
        }
        .accessibilityHidden(true)
    }

    private func legendDot(_ label: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            if let d = data {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text("\(d.totalToday - d.completedToday) left")
                        .font(.system(.caption2, design: .rounded).weight(.medium))
                        .foregroundStyle(.primary)
                }

                if d.streakDays > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("\(d.streakDays)d")
                            .font(.system(.caption2, design: .rounded).weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Text("Syncing...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - AI Insight Card

    @ViewBuilder
    private var aiInsightCard: some View {
        if let insight = data?.aiInsight, !insight.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.yellow)
                    Text("Insight")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.yellow)
                }

                Text(insight)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.yellow.opacity(0.1))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Insight: \(insight)")
        } else if data != nil {
            // Early days — show contextual prompt instead of empty space
            earlyDayPrompt
        }
    }

    @ViewBuilder
    private var earlyDayPrompt: some View {
        let remaining = (data?.totalToday ?? 0) - (data?.completedToday ?? 0)
        let hasCheckIn = data?.nextCheckIn != nil

        VStack(alignment: .leading, spacing: 4) {
            if remaining == 0 && (data?.totalToday ?? 0) == 0 {
                Text("Tap + to add your first task")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            } else if hasCheckIn {
                Text("Try a quick check-in →")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text("Your patterns are building...")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Background Gradient

    private var timeOfDayGradient: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let colors: [Color] = {
            switch hour {
            case 5..<8: return [Color(red: 0.95, green: 0.6, blue: 0.3), Color(red: 0.15, green: 0.1, blue: 0.2)] // warm dawn
            case 8..<12: return [Color(red: 0.2, green: 0.35, blue: 0.5), Color(red: 0.08, green: 0.08, blue: 0.12)] // morning blue
            case 12..<17: return [Color(red: 0.15, green: 0.25, blue: 0.45), Color(red: 0.06, green: 0.06, blue: 0.1)] // afternoon
            case 17..<20: return [Color(red: 0.6, green: 0.3, blue: 0.2), Color(red: 0.1, green: 0.06, blue: 0.12)] // sunset
            default: return [Color(red: 0.1, green: 0.08, blue: 0.2), Color(red: 0.04, green: 0.04, blue: 0.08)] // night
            }
        }()

        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}
#endif
