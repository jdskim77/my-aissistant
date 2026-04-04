import SwiftUI

struct VoiceModeSelectionView: View {
    let onContinue: () -> Void
    @AppStorage(AppConstants.voiceModeDefaultKey) private var voiceModeDefault = true
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(AppColors.accent)

                Text("How Do You Want\nto Chat?")
                    .font(AppFonts.display(28))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Choose your preferred way to interact\nwith your AI assistant.")
                    .font(AppFonts.body(15))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 16) {
                    modeCard(
                        icon: "waveform.circle.fill",
                        title: "Voice Mode",
                        subtitle: "Talk naturally, hands-free. Your assistant listens and responds aloud.",
                        isSelected: voiceModeDefault
                    ) {
                        voiceModeDefault = true
                    }

                    modeCard(
                        icon: "keyboard",
                        title: "Text Mode",
                        subtitle: "Type your messages. Responses appear as text.",
                        isSelected: !voiceModeDefault
                    ) {
                        voiceModeDefault = false
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Text("You can change this anytime in Settings.")
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)

            Spacer()

            Button(action: onContinue) {
                Text("Continue")
                    .font(AppFonts.bodyMedium(17))
                    .foregroundColor(AppColors.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.accent)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
        }
    }

    private func modeCard(
        icon: String,
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(isSelected ? AppColors.accent : AppColors.textMuted)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textPrimary)
                    Text(subtitle)
                        .font(AppFonts.body(13))
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? AppColors.accent : AppColors.border)
            }
            .padding(16)
            .background(AppColors.card)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? AppColors.accent.opacity(0.4) : AppColors.border.opacity(0.5),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
