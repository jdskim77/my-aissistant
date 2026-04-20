import SwiftUI

/// Minimal "what shapes today" detail: weather + sunrise/sunset + the
/// current check-in slot. Kept intentionally small — feature scope is
/// just Home-chip details. Future Phases can expand to daylight remaining,
/// moon phase, AI read, etc. without changing the chip.
struct TodaysContextSheet: View {
    let snapshot: WeatherSnapshot?
    let isLoading: Bool
    let isAuthorized: Bool
    /// True when the user has actively denied location permission. Distinct
    /// from `!isAuthorized`, which also covers `.notDetermined` — in the
    /// denied case the only way to recover is through Settings, so the CTA
    /// deep-links there instead of uselessly re-prompting.
    let isDenied: Bool
    let currentSlot: CheckInTime
    let onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        snapshot: WeatherSnapshot?,
        isLoading: Bool,
        isAuthorized: Bool,
        isDenied: Bool = false,
        currentSlot: CheckInTime,
        onRefresh: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.isLoading = isLoading
        self.isAuthorized = isAuthorized
        self.isDenied = isDenied
        self.currentSlot = currentSlot
        self.onRefresh = onRefresh
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    weatherCard
                    if snapshot?.sunrise != nil && snapshot?.sunset != nil {
                        sunCard
                    }
                    slotCard
                }
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await MainActor.run { onRefresh() } }
            .task {
                // If the user has already granted permission but the cache
                // was never populated (e.g. cold launch, chip tapped before
                // Home's background refresh completed), fetch now so the
                // sheet isn't stuck on "unavailable".
                if snapshot == nil && isAuthorized && !isLoading {
                    onRefresh()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Weather Card

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WEATHER")
                .font(AppFonts.label(11))
                .tracking(0.8)
                .foregroundColor(AppColors.textMuted)

            if let snap = snapshot {
                weatherLoaded(snap)
            } else if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Fetching weather…")
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.textMuted)
                }
            } else if !isAuthorized {
                VStack(alignment: .leading, spacing: 12) {
                    Text(isDenied
                        ? "Location access is off. Open Settings to turn it on and see local weather."
                        : "Enable location to see local weather and personalize your day.")
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Haptics.light()
                        if isDenied {
                            // Denial is persistent — CLLocationManager won't
                            // re-prompt. Deep-link into Settings so the user
                            // has a path to recover from the dead-end.
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } else {
                            onRefresh()
                        }
                    } label: {
                        Text(isDenied ? "Open Settings" : "Enable Location")
                            .font(AppFonts.bodyMedium(14))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppColors.accent)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.scale)
                }
            } else {
                Text("Weather unavailable")
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textMuted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppColors.card)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
        )
    }

    private func weatherLoaded(_ snap: WeatherSnapshot) -> some View {
        HStack(spacing: 14) {
            Image(systemName: snap.conditionSymbolName)
                .font(.system(size: 32, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(AppColors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(formatted(snap.temperature))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .monospacedDigit()
                Text(snap.conditionDescription)
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            if let high = snap.dailyHigh, let low = snap.dailyLow {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("H \(formatted(high))")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textSecondary)
                        .monospacedDigit()
                    Text("L \(formatted(low))")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textMuted)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Sun Card

    @ViewBuilder
    private var sunCard: some View {
        if let sunrise = snapshot?.sunrise, let sunset = snapshot?.sunset {
            HStack(spacing: 0) {
                sunStat(icon: "sunrise.fill", label: "Sunrise", date: sunrise, color: AppColors.accentWarm)
                    .frame(maxWidth: .infinity)
                Rectangle()
                    .fill(AppColors.border)
                    .frame(width: 1, height: 36)
                sunStat(icon: "sunset.fill", label: "Sunset", date: sunset, color: AppColors.skyBlue)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppColors.card)
                    .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
            )
        }
    }

    private func sunStat(icon: String, label: String, date: Date, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(label.uppercased())
                    .font(AppFonts.label(10))
                    .tracking(0.6)
                    .foregroundColor(AppColors.textMuted)
            }
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textPrimary)
                .monospacedDigit()
        }
    }

    // MARK: - Slot Card

    private var slotCard: some View {
        HStack(spacing: 12) {
            Image(systemName: currentSlot.sfSymbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(currentSlot.color)
                .frame(width: 36, height: 36)
                .background(currentSlot.color.opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("CURRENT SLOT")
                    .font(AppFonts.label(11))
                    .tracking(0.8)
                    .foregroundColor(AppColors.textMuted)
                Text(currentSlot.rawValue)
                    .font(AppFonts.heading(15))
                    .foregroundColor(AppColors.textPrimary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppColors.card)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
        )
    }

    // MARK: - Helpers

    private func formatted(_ m: Measurement<UnitTemperature>) -> String {
        Measurement(value: m.value.rounded(), unit: m.unit)
            .formatted(.measurement(width: .narrow, usage: .weather))
    }
}
