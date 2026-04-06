import SwiftUI

struct OnboardingQuickRateView: View {
    @Binding var ratings: [LifeDimension: Int]
    let onContinue: () -> Void
    @State private var appeared = false

    private let dimensions: [(LifeDimension, String, String)] = [
        (.physical,  "How's your body feeling lately?",
         "Energy, sleep, movement, nutrition"),
        (.mental,    "How sharp and engaged does your mind feel?",
         "Focus, learning, creativity, clarity"),
        (.emotional, "How connected and at peace do you feel?",
         "Relationships, stress, emotional resilience"),
        (.spiritual, "How much are you giving back to the people and world around you?",
         "Helping others, sharing skills, contribution, community"),
    ]

    private let ratingOptions: [(score: Int, label: String)] = [
        (1, "Struggling"),
        (3, "Could be\nbetter"),
        (5, "Okay"),
        (7, "Good"),
        (9, "Thriving"),
    ]

    private var allRated: Bool {
        LifeDimension.scored.allSatisfy { ratings[$0] != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Rate Your Life")
                        .font(AppFonts.display(24))
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.top, 20)

                    ForEach(dimensions, id: \.0) { dim, question, subtitle in
                        dimensionCard(dim: dim, question: question, subtitle: subtitle)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)

            // Continue button
            VStack(spacing: 0) {
                Divider()
                Button(action: onContinue) {
                    Text("See My Compass")
                        .font(AppFonts.bodyMedium(17))
                        .foregroundColor(AppColors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(allRated ? AppColors.accent : AppColors.textMuted)
                        .cornerRadius(14)
                }
                .disabled(!allRated)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .background(AppColors.surface)
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }

    // MARK: - Dimension Card

    private func dimensionCard(dim: LifeDimension, question: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: dim.icon)
                    .font(AppFonts.bodyMedium(18))
                    .foregroundColor(dim.color)
                    .frame(width: 36, height: 36)
                    .background(dim.color.opacity(0.12))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(dim.label)
                        .font(AppFonts.heading(16))
                        .foregroundColor(AppColors.textPrimary)
                    Text(subtitle)
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textMuted)
                }
                Spacer()
            }

            // Question
            Text(question)
                .font(AppFonts.body(15))
                .foregroundColor(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Rating circles
            HStack(spacing: 0) {
                ForEach(ratingOptions, id: \.score) { option in
                    let isSelected = ratings[dim] == option.score

                    Button {
                        Haptics.light()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            ratings[dim] = option.score
                        }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(isSelected ? dim.color : AppColors.surface)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle()
                                            .stroke(isSelected ? Color.clear : AppColors.border, lineWidth: 1)
                                    )
                                    .scaleEffect(isSelected ? 1.1 : 1.0)

                                Text("\(option.score)")
                                    .font(AppFonts.bodyMedium(16))
                                    .foregroundColor(isSelected ? .white : AppColors.textPrimary)
                            }

                            Text(option.label)
                                .font(AppFonts.caption(10))
                                .foregroundColor(isSelected ? dim.color : AppColors.textMuted)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(height: 26)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.label), score \(option.score)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    ratings[dim] != nil ? dim.color.opacity(0.3) : AppColors.border,
                    lineWidth: ratings[dim] != nil ? 1.5 : 1
                )
        )
    }
}
