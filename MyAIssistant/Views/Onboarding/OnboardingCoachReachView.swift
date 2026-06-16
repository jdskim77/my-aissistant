import SwiftUI

/// Coach-reach consent screen — primes the user to enable proactive nudges
/// during onboarding rather than burying the toggle in Settings.
///
/// Without this screen the proactive coaching pillar ships dark: `nudgeEnabledKey`
/// defaults to false and no other onboarding screen sets it true. A user who
/// finishes onboarding never hears from the coach unsolicited until they find
/// Settings → Coach. The make-or-break "uncannily-timed nudge per week" can
/// never fire on day 1.
///
/// Default frequency is `.balanced` (2/day cap). User can choose `.gentle`
/// (1/day) or `.off` (declines proactive reach entirely). Whatever they pick,
/// quiet hours from `AppConstants` apply — this screen does not surface
/// quiet-hour configuration; that lives in Settings → Coach.
struct OnboardingCoachReachView: View {

    let weakestDimension: LifeDimension
    let intention: String
    let onContinue: () -> Void

    @AppStorage(AppConstants.nudgeEnabledKey)
    private var nudgesEnabled: Bool = false

    @AppStorage(AppConstants.nudgeFrequencyKey)
    private var frequencyRaw: String = NudgeFrequency.balanced.rawValue

    @State private var selection: Choice = .balanced

    enum Choice: String, CaseIterable, Identifiable {
        case gentle, balanced, off
        var id: String { rawValue }

        var label: String {
            switch self {
            case .gentle:   return "Gentle"
            case .balanced: return "Balanced"
            case .off:      return "Not now"
            }
        }

        var detail: String {
            switch self {
            case .gentle:   return "1 nudge a day, max"
            case .balanced: return "Up to 2 a day, when it matters"
            case .off:      return "I'll come to you. No proactive nudges."
            }
        }

        var icon: String {
            switch self {
            case .gentle:   return "leaf"
            case .balanced: return "sparkles"
            case .off:      return "moon.zzz"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 12)

                Image(systemName: "wave.3.right")
                    .font(.system(size: 48))
                    .foregroundColor(AppColors.accent)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text("Should your coach reach out?")
                        .font(AppFonts.display(28))
                        .foregroundColor(AppColors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(framedRationale)
                        .font(AppFonts.body(16))
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    ForEach(Choice.allCases) { choice in
                        choiceRow(choice)
                    }
                }
                .padding(.horizontal, 20)

                Text("You can change this any time in Settings → Coach.")
                    .font(AppFonts.caption(13))
                    .foregroundColor(AppColors.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer().frame(height: 8)

                Button(action: confirm) {
                    Text(selection == .off ? "Continue without nudges" : "Sounds good")
                        .font(AppFonts.bodyMedium(17))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)
                .accessibilityLabel(selection == .off ? "Continue without nudges" : "Sounds good")
                .accessibilityHint("Confirms your nudge preference and continues to the next step")

                Spacer().frame(height: 16)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.background.ignoresSafeArea())
    }

    private var framedRationale: String {
        let trimmed = intention.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return "Your coach will check in about \(trimmed). Specific, well-timed — silenceable any time."
        }
        return "Your coach will check in about \(weakestDimension.label.lowercased()) when the moment fits. Specific, well-timed — silenceable any time."
    }

    private func choiceRow(_ choice: Choice) -> some View {
        Button(action: { selection = choice }) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: choice.icon)
                    .font(.system(size: 20))
                    .foregroundColor(selection == choice ? AppColors.accent : AppColors.textSecondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(choice.label)
                        .font(AppFonts.bodyMedium(16))
                        .foregroundColor(AppColors.textPrimary)
                    Text(choice.detail)
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: selection == choice ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(selection == choice ? AppColors.accent : AppColors.border)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selection == choice ? AppColors.accent : AppColors.border, lineWidth: selection == choice ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(choice.label): \(choice.detail)")
        .accessibilityAddTraits(selection == choice ? .isSelected : [])
    }

    private func confirm() {
        Haptics.light()
        switch selection {
        case .gentle:
            nudgesEnabled = true
            frequencyRaw = NudgeFrequency.gentle.rawValue
        case .balanced:
            nudgesEnabled = true
            frequencyRaw = NudgeFrequency.balanced.rawValue
        case .off:
            nudgesEnabled = false
            frequencyRaw = NudgeFrequency.off.rawValue
        }
        onContinue()
    }
}

#Preview {
    OnboardingCoachReachView(
        weakestDimension: .physical,
        intention: "move every morning",
        onContinue: {}
    )
}
