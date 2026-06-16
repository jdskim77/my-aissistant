import SwiftUI

struct MoodPicker: View {
    @Binding var selectedMood: Int?
    /// Fired after selection so the parent can auto-advance the flow.
    /// Optional so callers that just want a picker (no advance) keep working.
    var onSelect: ((Int) -> Void)? = nil
    /// When true, taps are ignored — used by the parent during the
    /// 250ms auto-advance debounce so a fast double-tap can't skip a step.
    var isLocked: Bool = false

    /// Per-tap counter so `.sensoryFeedback(.selection, trigger:)` fires
    /// even when the user re-taps the same value (e.g. after Back-nav
    /// from the next step). Using `selectedMood` as the trigger swallows
    /// the haptic on identical re-selection because the value didn't
    /// change. BUG-06 from the auto-advance QA pass.
    @State private var hapticTick = 0

    private let moods: [(emoji: String, label: String, value: Int)] = [
        ("😔", "Rough", 1),
        ("😕", "Low", 2),
        ("😐", "Okay", 3),
        ("🙂", "Good", 4),
        ("😄", "Great", 5)
    ]

    var body: some View {
        VStack(spacing: 10) {
            Text("How are you feeling?")
                .font(AppFonts.heading(16))
                .foregroundColor(AppColors.textPrimary)

            HStack(spacing: 16) {
                ForEach(moods, id: \.value) { mood in
                    Button {
                        guard !isLocked else { return }
                        hapticTick &+= 1
                        withAnimation(.spring(response: 0.3)) {
                            selectedMood = mood.value
                        }
                        onSelect?(mood.value)
                    } label: {
                        VStack(spacing: 4) {
                            Text(mood.emoji)
                                .font(AppFonts.icon(selectedMood == mood.value ? 36 : 28))

                            Text(mood.label)
                                .font(AppFonts.caption(11))
                                .foregroundColor(
                                    selectedMood == mood.value
                                        ? AppColors.accent
                                        : AppColors.textMuted
                                )
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                        .background(
                            selectedMood == mood.value
                                ? AppColors.accentLight
                                : Color.clear
                        )
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(mood.label), \(mood.value) of 5")
                    .accessibilityAddTraits(selectedMood == mood.value ? [.isSelected] : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: hapticTick)
    }
}
