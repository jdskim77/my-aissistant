import SwiftUI

struct MoodPicker: View {
    @Binding var selectedMood: Int?

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
                        withAnimation(.spring(response: 0.3)) {
                            selectedMood = mood.value
                        }
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
                }
            }
        }
    }
}
