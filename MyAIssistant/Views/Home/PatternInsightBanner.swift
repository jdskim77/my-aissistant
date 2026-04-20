import SwiftUI

/// A slim, dismissible banner that surfaces a Pattern Insight above the Hero.
/// Replaces the resident Pattern Insight card to reduce Home-screen density
/// and give the insight more of a "surfacing moment" (per-day dismissable).
struct PatternInsightBanner: View {
    let insight: InsightEngine.Insight
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: insight.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.accent)
                .frame(width: 28, height: 28)
                .background(AppColors.accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("PATTERN INSIGHT")
                    .font(AppFonts.label(9))
                    .tracking(0.7)
                    .foregroundColor(AppColors.accent)
                Text(insight.text)
                    .font(AppFonts.body(13))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                Haptics.light()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss pattern insight")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.accent.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.accent.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pattern insight: \(insight.text)")
    }

    // MARK: - Dismissal tracking (per-day UserDefaults)

    static let dismissKeyPrefix = "patternInsightBanner.dismissed."

    /// Returns true if the banner has been dismissed for the current ordinal day.
    /// Deterministic per-day so the banner re-appears the next day if insight is
    /// still relevant.
    static func isDismissedToday() -> Bool {
        UserDefaults.standard.bool(forKey: dismissKey(for: Date()))
    }

    /// Mark the banner as dismissed for today.
    static func markDismissedToday() {
        UserDefaults.standard.set(true, forKey: dismissKey(for: Date()))
    }

    private static func dismissKey(for date: Date) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return "\(dismissKeyPrefix)\(day)"
    }

    /// Sweeps stale per-day dismissal keys older than the given window.
    /// Called from app launch so the plist doesn't accumulate one key per
    /// day indefinitely (~365/year, non-trivial after multi-year retention
    /// since UserDefaults is loaded eagerly at launch).
    static func pruneStaleDismissals(olderThan days: Int = 30) {
        let defaults = UserDefaults.standard
        let today = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let cutoff = today - days
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(dismissKeyPrefix) {
            let suffix = key.dropFirst(dismissKeyPrefix.count)
            guard let day = Int(suffix), day < cutoff else { continue }
            defaults.removeObject(forKey: key)
        }
    }
}
