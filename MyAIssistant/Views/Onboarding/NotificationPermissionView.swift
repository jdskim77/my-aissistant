import SwiftUI
import UserNotifications

struct NotificationPermissionView: View {
    let onAllow: () -> Void
    let onSkip: () -> Void
    /// When true, shows the 4 check-in time slots inline above the
    /// permission-priming benefit rows. Used by `OnboardingClosingView`
    /// (the merged SignIn + Name + Notification screen — step 2 #4):
    /// the schedule no longer earns its own destination but still
    /// appears as context so the user knows what they're being asked
    /// to allow notifications for. Default `false` preserves the
    /// view's prior behavior wherever it might still be used solo.
    var showsScheduleContext: Bool = false

    @State private var appeared = false
    @State private var requesting = false
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "bell.badge.fill")
                    .font(AppFonts.icon(64))
                    .foregroundColor(AppColors.accent)
                    .scaleEffect(appeared ? 1 : 0.6)

                VStack(spacing: 12) {
                    Text("Want gentle reminders?")
                        .font(AppFonts.display(28))
                        .foregroundColor(AppColors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("I'll send a quiet nudge for each check-in. No spam, no marketing.")
                        .font(AppFonts.body(15))
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(alignment: .leading, spacing: 14) {
                    if showsScheduleContext {
                        scheduleContext
                    } else {
                        benefitRow(
                            icon: "bell.fill",
                            title: "4 check-ins a day",
                            subtitle: "Morning, midday, afternoon, night"
                        )
                    }
                    benefitRow(
                        icon: "flame.fill",
                        title: "Streak protection",
                        subtitle: "I'll let you know if your streak is at risk"
                    )
                    benefitRow(
                        icon: "hand.raised.fill",
                        title: "You're in control",
                        subtitle: "Turn off any time in Settings"
                    )
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)

            Spacer()

            VStack(spacing: 12) {
                Button(action: primaryButtonAction) {
                    Text(primaryButtonTitle)
                        .font(AppFonts.bodyMedium(17))
                        .foregroundColor(AppColors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.accent)
                        .cornerRadius(14)
                }
                .disabled(requesting)
                .accessibilityHint(primaryButtonHint)

                Button(action: {
                    Haptics.selection()
                    onSkip()
                }) {
                    Text("Not now")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityHint("Skips this step and continues")
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
            loadAuthStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // User may have toggled notifications in Settings and returned —
            // re-check auth status so the button label and onAllow() routing
            // reflect reality.
            if newPhase == .active {
                loadAuthStatus()
            }
        }
    }

    // MARK: - Permission state

    /// Title shown on the primary button. Adapts to whether the user has
    /// previously denied notification permission — if so, the in-app prompt
    /// would silently no-op (`requestAuthorization` returns false without
    /// showing any system UI), so we change the affordance to "Open Settings"
    /// and deep-link there.
    private var primaryButtonTitle: String {
        if requesting { return "Requesting…" }
        switch authStatus {
        case .denied:
            return "Open Settings"
        case .authorized, .provisional, .ephemeral:
            return "Continue"
        case .notDetermined:
            return "Enable Reminders"
        @unknown default:
            return "Enable Reminders"
        }
    }

    private var primaryButtonHint: String {
        switch authStatus {
        case .denied:
            return "Opens iOS Settings so you can enable notifications for Thrivn"
        case .authorized, .provisional, .ephemeral:
            return "Notifications are already enabled — continue"
        default:
            return "Asks for notification permission"
        }
    }

    private func primaryButtonAction() {
        switch authStatus {
        case .denied:
            openSystemSettings()
        case .authorized, .provisional, .ephemeral:
            Haptics.success()
            onAllow()
        case .notDetermined:
            requestPermission()
        @unknown default:
            requestPermission()
        }
    }

    private func loadAuthStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                authStatus = settings.authorizationStatus
            }
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        // Don't auto-advance — the user needs to actually toggle the switch
        // in Settings, then return to the app. They can tap "Not now" if they
        // change their mind.
    }

    private func requestPermission() {
        guard !requesting else { return }
        requesting = true
        Task {
            // Re-check current status before requesting. The user may have
            // toggled the permission in Settings and returned faster than the
            // scenePhase observer could refresh `authStatus`. Calling
            // `requestAuthorization` on an already-determined status either
            // no-ops (denied) or returns true (authorized) without showing UI
            // — we want to honor the real state instead of overwriting it.
            let center = UNUserNotificationCenter.current()
            let currentSettings = await center.notificationSettings()
            if currentSettings.authorizationStatus != .notDetermined {
                await MainActor.run {
                    requesting = false
                    authStatus = currentSettings.authorizationStatus
                    switch currentSettings.authorizationStatus {
                    case .authorized, .provisional, .ephemeral:
                        Haptics.success()
                    default:
                        Haptics.light()
                    }
                    onAllow()
                }
                return
            }

            let granted = (try? await center
                .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            await MainActor.run {
                requesting = false
                authStatus = granted ? .authorized : .denied
                if granted {
                    Haptics.success()
                } else {
                    Haptics.light()
                }
                // Always advance — the system prompt has been shown.
                onAllow()
            }
        }
    }

    /// Inline schedule context shown when `showsScheduleContext` is true.
    /// Uses the canonical `CheckInTime` enum (Models/CheckIn.swift) — no
    /// onboarding-local copies. Replaces the 4-slot dedicated screen
    /// from the prior 10-screen flow (step 2 #4).
    private var scheduleContext: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Image(systemName: "bell.fill")
                    .font(AppFonts.bodyMedium(20))
                    .foregroundColor(AppColors.accent)
                    .frame(width: 44, height: 44)
                    .background(AppColors.accent.opacity(0.12))
                    .cornerRadius(12)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("4 check-ins a day")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textPrimary)
                    Text("15 seconds each — set later in Settings")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textMuted)
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("4 check-ins a day. 15 seconds each, set later in Settings.")

            // ViewThatFits picks the horizontal row when it fits, the
            // 2x2 grid when it doesn't (iPhone SE + XXL Dynamic Type
            // would clip the four pills in a single row — QA BUG-04).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(CheckInTime.allCases) { slot in
                        slotPill(slot)
                    }
                }
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(CheckInTime.allCases) { slot in
                        slotPill(slot)
                    }
                }
            }
            .padding(.top, 4)
            .padding(.leading, 58) // align under the title text, not the icon
        }
    }

    private func slotPill(_ slot: CheckInTime) -> some View {
        VStack(spacing: 2) {
            Text(slot.icon)
                .font(AppFonts.body(14))
                .accessibilityHidden(true)
            Text(slot.timeLabel)
                .font(AppFonts.caption(10))
                .foregroundColor(slot.color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(slot.color.opacity(0.10))
        .cornerRadius(8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(slot.title) at \(slot.timeLabel)")
    }

    private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(AppFonts.bodyMedium(20))
                .foregroundColor(AppColors.accent)
                .frame(width: 44, height: 44)
                .background(AppColors.accent.opacity(0.12))
                .cornerRadius(12)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(AppColors.textPrimary)
                Text(subtitle)
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}
