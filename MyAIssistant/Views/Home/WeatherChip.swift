import SwiftUI

/// Compact weather pill for the Home header — sits to the right of the
/// greeting and aligns roughly with the date line. Tapping always opens
/// the Today's Context sheet; permission prompts are handled there so the
/// first tap never surprises the user with a system dialog.
struct WeatherChip: View {
    let snapshot: WeatherSnapshot?
    let isLoading: Bool
    let isAuthorized: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            content
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    Capsule()
                        .fill(AppColors.card)
                        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
                )
                // 44pt minimum hit target — the visible capsule stays
                // compact but tap area meets Apple's guideline.
                .contentShape(Capsule())
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.scale)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens today's weather and context")
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            HStack(spacing: 6) {
                Image(systemName: snapshot.conditionSymbolName)
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(AppColors.accent)
                Text(formattedTemperature(snapshot.temperature))
                    .font(AppFonts.bodyMedium(14))
                    .foregroundColor(AppColors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else if isLoading {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7)
                Text("Loading")
                    .font(AppFonts.bodyMedium(14))
                    .foregroundColor(AppColors.textMuted)
                    .lineLimit(1)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: isAuthorized ? "cloud" : "location.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppColors.textMuted)
                Text(isAuthorized ? "Weather" : "Enable")
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)
                    .lineLimit(1)
            }
        }
    }

    private func formattedTemperature(_ measurement: Measurement<UnitTemperature>) -> String {
        Measurement(value: measurement.value.rounded(), unit: measurement.unit)
            .formatted(.measurement(width: .narrow, usage: .weather))
    }

    private var accessibilityLabel: String {
        if let snapshot {
            // Action-first phrasing; VoiceOver already announces "button".
            return "\(snapshot.conditionDescription), \(formattedTemperature(snapshot.temperature))"
        } else if isLoading {
            return "Loading weather"
        } else if isAuthorized {
            return "Weather"
        } else {
            return "Weather, location off"
        }
    }
}
