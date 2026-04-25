import SwiftUI

/// Final onboarding screen that absorbs Sign-in + Name confirm + Notification
/// permission into a single value-first close. Step 2 of the onboarding
/// restructure (handoff §5). Replaces three dedicated screens (Sign-in,
/// Name Capture, Notification) with one coordinator that walks the user
/// through three internal stages back-to-back.
///
/// Stage flow:
/// 1. `.signIn` — Apple sign-in with "Sign in to save your Compass" CTA.
///    Skip path preserves BYOK ("Continue without an account"). Apple may
///    or may not return a name; either way we move to .nameConfirm.
/// 2. `.nameConfirm` — pre-filled from Apple if provided (often
///    misspelled — never auto-skip), editable inline, also skippable.
/// 3. `.notification` — Notification permission with the 4 check-in slots
///    rendered inline as schedule context (see
///    `NotificationPermissionView.showsScheduleContext`).
///
/// On completion of stage 3 (allow OR skip), `onComplete` fires and the
/// container persists everything via `completeOnboarding()`.
///
/// Bag of responsibilities kept deliberately thin: each stage delegates
/// rendering to its existing view (SignInWithAppleView, NameCaptureView,
/// NotificationPermissionView). This view is just a switch + state
/// machine — no business logic of its own.
struct OnboardingClosingView: View {
    @Binding var capturedName: String
    /// Stage owned by the container so it survives any TabView
    /// re-mount of this view (QA BUG-01). If the closing view re-
    /// initialised its own `@State`, a backtrack-and-return path
    /// would re-show Apple Sign-in even though the user already
    /// completed it — risking duplicate backend account creation.
    /// Keeping the stage in the container makes re-mount idempotent.
    @Binding var stage: Stage
    let onComplete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Stage: String {
        case signIn
        case nameConfirm
        case notification
    }

    var body: some View {
        // No outer chrome — each stage's existing view paints its own
        // backgrounds, buttons, and spacing. Keeping this empty avoids
        // double-padding when the user switches stages.
        Group {
            switch stage {
            case .signIn:
                SignInWithAppleView(
                    onSignedIn: { name in
                        if let name, !name.isEmpty {
                            capturedName = name
                        }
                        advance(to: .nameConfirm)
                    },
                    onSkip: { advance(to: .nameConfirm) }
                )
                // Override the headline copy for the closing-screen
                // context: "Sign in to save your Compass" frames the
                // value, not the auth. The view itself still says
                // "Sign in to get started" — leaving that as a future
                // edit (would require a copy-binding inside that
                // view, out of scope for this commit).
            case .nameConfirm:
                NameCaptureView(
                    name: $capturedName,
                    onContinue: { advance(to: .notification) },
                    onSkip: { advance(to: .notification) }
                )
            case .notification:
                NotificationPermissionView(
                    onAllow: onComplete,
                    onSkip: onComplete,
                    showsScheduleContext: true
                )
            }
        }
        .transition(.opacity)
        // Reduce Motion gate: opacity transitions are intrinsically
        // motion-light, but explicitly disable the easeInOut so the
        // switch lands instantly for users who opted out (QA BUG-06).
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: stage)
    }

    private func advance(to next: Stage) {
        // Stage transitions are linear and one-way. We don't need a
        // back path inside this view — the container's top-bar back
        // button is suppressed on this final screen, and pressing
        // back from a sub-stage would mean leaving onboarding entirely
        // (already handled at the OS gesture level inside SignIn /
        // NameCapture / Notification — none of which mutate state on
        // dismiss).
        stage = next
    }
}
