import SwiftUI
import AuthenticationServices

/// Sign in with Apple step in onboarding.
/// On success, calls `onSignedIn` with the user's display name (if provided).
/// On skip, calls `onSkip` — the user can still use the app with BYOK.
struct SignInWithAppleView: View {
    let onSignedIn: (String?) -> Void
    let onSkip: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.keychainService) private var keychainService
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "applelogo")
                    .font(AppFonts.icon(56))
                    .foregroundColor(AppColors.textPrimary)
                    .scaleEffect(appeared ? 1 : 0.6)

                VStack(spacing: 8) {
                    Text("Sign in to get started")
                        .font(AppFonts.display(24))
                        .foregroundColor(AppColors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Securely sign in with Apple to save your data and chat with your AI coach.")
                        .font(AppFonts.body(15))
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(alignment: .leading, spacing: 12) {
                    benefitRow(icon: "lock.fill", text: "Your data syncs across devices")
                    benefitRow(icon: "sparkles", text: "Free 100 AI messages per month")
                    benefitRow(icon: "hand.raised.fill", text: "No tracking, no spam, ever")
                }
                .padding(.top, 8)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)

            Spacer()

            // Error message
            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.coral)
                    Text(errorMessage)
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.coral)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            // Apple Sign-In button (with loading overlay)
            ZStack {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .cornerRadius(14)
                .disabled(isProcessing)
                .opacity(isProcessing ? 0.5 : 1)

                if isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(colorScheme == .dark ? .black : .white)
                        Text("Signing you in…")
                            .font(AppFonts.bodyMedium(15))
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                    }
                    .accessibilityLabel("Signing in, please wait")
                }
            }
            .padding(.horizontal, 24)

            // Privacy disclosure under the button
            Text("We use your name and email only to sync across devices. No marketing.")
                .font(AppFonts.caption(11))
                .foregroundColor(AppColors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 8)

            // Skip option — plain English, larger touch target
            Button {
                Haptics.selection()
                onSkip()
            } label: {
                Text("Continue without an account")
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .accessibilityHint("Skip sign-in and continue with limited features")
            .opacity(appeared ? 1 : 0)
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.accent)
                .frame(width: 24)
            Text(text)
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.horizontal, 32)
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                errorMessage = "Couldn't read Apple credentials. Please try again."
                return
            }

            // Build the display name from given/family if Apple shared it (only on first sign-in)
            let fullName: String? = {
                let parts = [credential.fullName?.givenName, credential.fullName?.familyName]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                return parts.isEmpty ? nil : parts.joined(separator: " ")
            }()
            let email = credential.email

            isProcessing = true
            errorMessage = nil

            Task {
                do {
                    let backend = ThrivnBackendService(keychain: keychainService)
                    let user = try await backend.signInWithApple(
                        identityToken: identityToken,
                        fullName: fullName,
                        email: email
                    )
                    await MainActor.run {
                        isProcessing = false
                        Haptics.success()
                        onSignedIn(user.display_name ?? fullName)
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        errorMessage = "Sign-in failed: \(error.localizedDescription)"
                    }
                }
            }

        case .failure(let error):
            // User cancellation is not an error
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = "Sign-in failed: \(error.localizedDescription)"
        }
    }
}
