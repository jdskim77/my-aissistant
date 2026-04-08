import SwiftUI

struct NameCaptureView: View {
    @Binding var name: String
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var appeared = false
    @FocusState private var isFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "person.fill.questionmark")
                    .font(AppFonts.icon(64))
                    .foregroundColor(AppColors.accent)
                    .scaleEffect(appeared ? 1 : 0.6)

                VStack(spacing: 12) {
                    Text("What should I call you?")
                        .font(AppFonts.display(28))
                        .foregroundColor(AppColors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Just your first name. I'll use it when we talk.")
                        .font(AppFonts.body(15))
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                TextField("First name", text: $name)
                    .font(AppFonts.body(17))
                    .foregroundColor(AppColors.textPrimary)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)
                    .submitLabel(.continue)
                    .focused($isFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(AppColors.card)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isFocused ? AppColors.accent : AppColors.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    .accessibilityLabel("Your first name")
                    .onSubmit {
                        if isValid {
                            Haptics.light()
                            onContinue()
                        }
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { isFocused = false }
                                .font(AppFonts.bodyMedium(15))
                                .foregroundColor(AppColors.accent)
                        }
                    }
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)

            Spacer()

            VStack(spacing: 12) {
                Button(action: {
                    Haptics.light()
                    onContinue()
                }) {
                    Text("Continue")
                        .font(AppFonts.bodyMedium(17))
                        .foregroundColor(AppColors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isValid ? AppColors.accent : AppColors.accent.opacity(0.4))
                        .cornerRadius(14)
                }
                .disabled(!isValid)
                .accessibilityHint("Saves your name and continues")

                Button(action: {
                    Haptics.selection()
                    onSkip()
                }) {
                    Text("Skip")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityHint("Skips naming and continues")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .opacity(appeared ? 1 : 0)
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            isFocused = true
        }
    }
}
