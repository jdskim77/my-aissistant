import SwiftUI

struct AIGreetingCard: View {
    let greeting: String
    let isAnimating: Bool
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 14) {
            AIActivityOrb(isActive: isAnimating, size: 36)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("Your AI Assistant")
                    .font(AppFonts.label(11))
                    .foregroundColor(AppColors.textMuted)
                    .textCase(.uppercase)

                Text(greeting)
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(AppFonts.label(11))
                    .foregroundColor(AppColors.textMuted)
                    .padding(6)
                    .background(AppColors.surface)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppColors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        colors: [
                            AppColors.accent.opacity(0.3),
                            AppColors.accentWarm.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .offset(y: appeared ? 0 : 15)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                appeared = true
            }
        }
    }
}
