import SwiftUI
import EventKit
import AuthenticationServices

struct CalendarImportView: View {
    @Environment(\.calendarSyncManager) private var calendarSyncManager
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false
    @State private var isSigningInGoogle = false
    @State private var googleAuthError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Apple Calendar section
                    appleCalendarSection

                    // Apple Reminders section
                    remindersSection

                    // Google Calendar section
                    googleCalendarSection

                    // Linked calendars
                    linkedCalendarsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Import Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.accent)
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    appeared = true
                }
                Task {
                    if calendarSyncManager?.appleCalendarAuthorized == true {
                        await calendarSyncManager?.loadAppleCalendars()
                    }
                    if calendarSyncManager?.remindersAuthorized == true {
                        await calendarSyncManager?.loadReminderLists()
                    }
                    // Load Google calendars if already connected
                    if await calendarSyncManager?.googleCalendarConnected() == true {
                        await calendarSyncManager?.loadGoogleCalendars()
                    }
                }
            }
        }
    }

    // MARK: - Apple Calendar Section

    private var appleCalendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(AppFonts.heading(20))
                    .foregroundColor(AppColors.accent)
                Text("Apple Calendar")
                    .font(AppFonts.heading(17))
                    .foregroundColor(AppColors.textPrimary)
            }

            if calendarSyncManager?.appleCalendarAuthorized == true {
                let calendars = calendarSyncManager?.appleCalendars ?? []
                if calendars.isEmpty {
                    Text("No calendars found.")
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.textMuted)
                } else {
                    ForEach(calendars, id: \.calendarIdentifier) { cal in
                        calendarRow(
                            name: cal.title,
                            color: Color(cgColor: cal.cgColor),
                            isLinked: isLinked(calendarID: cal.calendarIdentifier, source: .apple)
                        ) {
                            toggleLink(calendar: cal)
                        }
                    }
                }
            } else {
                Button {
                    Task {
                        _ = await calendarSyncManager?.requestAppleCalendarAccess()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open")
                            .font(AppFonts.bodyMedium(14))
                        Text("Grant Calendar Access")
                            .font(AppFonts.bodyMedium(14))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppColors.accent)
                    .cornerRadius(10)
                }
            }
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Reminders Section

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(AppFonts.heading(20))
                    .foregroundColor(AppColors.accentWarm)
                Text("Apple Reminders")
                    .font(AppFonts.heading(17))
                    .foregroundColor(AppColors.textPrimary)
            }

            if calendarSyncManager?.remindersAuthorized == true {
                let lists = calendarSyncManager?.reminderLists ?? []
                if lists.isEmpty {
                    Text("No reminder lists found.")
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.textMuted)
                } else {
                    ForEach(lists, id: \.calendarIdentifier) { list in
                        calendarRow(
                            name: list.title,
                            color: Color(cgColor: list.cgColor),
                            isLinked: isLinked(calendarID: list.calendarIdentifier, source: .reminders)
                        ) {
                            toggleReminderLink(list: list)
                        }
                    }
                }
            } else {
                Text("Import your Apple Reminders as tasks. Completions sync both ways.")
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textMuted)

                Button {
                    Task {
                        _ = await calendarSyncManager?.requestRemindersAccess()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checklist")
                            .font(AppFonts.bodyMedium(14))
                        Text("Connect Reminders")
                            .font(AppFonts.bodyMedium(14))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppColors.accentWarm)
                    .cornerRadius(10)
                }
            }
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Google Calendar Section

    private var googleCalendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(AppFonts.heading(20))
                    .foregroundColor(AppColors.coral)
                Text("Google Calendar")
                    .font(AppFonts.heading(17))
                    .foregroundColor(AppColors.textPrimary)
            }

            let googleCals = calendarSyncManager?.googleCalendars ?? []

            if !googleCals.isEmpty {
                // Show Google calendars when connected
                ForEach(googleCals) { cal in
                    calendarRow(
                        name: cal.displayName,
                        color: Color(hex: cal.backgroundColor?.replacingOccurrences(of: "#", with: "") ?? "4285F4"),
                        isLinked: isLinked(calendarID: cal.id, source: .google)
                    ) {
                        toggleGoogleLink(calendar: cal)
                    }
                }

                Button {
                    Task {
                        await calendarSyncManager?.googleService.signOut()
                        calendarSyncManager?.googleCalendars = []
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(AppFonts.bodyMedium(13))
                        Text("Sign Out")
                            .font(AppFonts.bodyMedium(13))
                    }
                    .foregroundColor(AppColors.coral)
                    .padding(.top, 4)
                }
            } else {
                // Sign-in button
                Text("Import events from your Google Calendar. Events sync as read-only.")
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textMuted)

                if let error = googleAuthError {
                    Text(error)
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.coral)
                }

                Button {
                    signInWithGoogle()
                } label: {
                    HStack(spacing: 8) {
                        if isSigningInGoogle {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "globe")
                                .font(AppFonts.bodyMedium(14))
                        }
                        Text("Sign in with Google")
                            .font(AppFonts.bodyMedium(14))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: "4285F4"))
                    .cornerRadius(10)
                }
                .disabled(isSigningInGoogle)
            }
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Linked Calendars

    private var linkedCalendarsSection: some View {
        let links = calendarSyncManager?.linkedCalendars() ?? []

        return Group {
            if !links.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Synced Calendars")
                        .font(AppFonts.heading(17))
                        .foregroundColor(AppColors.textPrimary)

                    ForEach(links, id: \.id) { link in
                        HStack(spacing: 12) {
                            Image(systemName: link.calendarSource.icon)
                                .font(AppFonts.body(16))
                                .foregroundColor(AppColors.accent)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.name)
                                    .font(AppFonts.bodyMedium(14))
                                    .foregroundColor(AppColors.textPrimary)
                                if let synced = link.lastSynced {
                                    Text("Last synced: \(synced.formatted(as: "MMM d, h:mm a"))")
                                        .font(AppFonts.caption(11))
                                        .foregroundColor(AppColors.textMuted)
                                }
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { link.enabled },
                                set: { _ in calendarSyncManager?.toggleCalendarLink(link) }
                            ))
                            .labelsHidden()
                            .tint(AppColors.accent)
                        }
                        .padding(12)
                        .background(AppColors.surface)
                        .cornerRadius(10)
                    }

                    // Sync now button
                    Button {
                        Task { await calendarSyncManager?.syncAll() }
                    } label: {
                        HStack(spacing: 6) {
                            if calendarSyncManager?.isSyncing == true {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(AppFonts.bodyMedium(14))
                            }
                            Text("Sync Now")
                                .font(AppFonts.bodyMedium(14))
                        }
                        .foregroundColor(AppColors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.accentLight)
                        .cornerRadius(10)
                    }
                    .disabled(calendarSyncManager?.isSyncing == true)
                }
                .padding(16)
                .background(AppColors.card)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Google OAuth

    private func signInWithGoogle() {
        guard let syncManager = calendarSyncManager else { return }

        Task {
            guard let authURL = await syncManager.googleService.authorizationURL() else {
                googleAuthError = "Google Calendar is not configured. Add a Google OAuth client ID."
                return
            }

            isSigningInGoogle = true
            googleAuthError = nil

            // Present ASWebAuthenticationSession
            let callbackURL = await startGoogleAuth(url: authURL)

            if let callbackURL,
               let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
               let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                do {
                    try await syncManager.googleService.exchangeCodeForTokens(code)
                    await syncManager.loadGoogleCalendars()
                } catch {
                    googleAuthError = "Sign-in failed: \(error.localizedDescription)"
                }
            } else {
                googleAuthError = "Sign-in was cancelled."
            }

            isSigningInGoogle = false
        }
    }

    @MainActor
    private func startGoogleAuth(url: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "com.myaissistant"
            ) { callbackURL, error in
                if let error {
                    _ = error // auth error handled by caller
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: callbackURL)
                }
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = GoogleAuthPresenter.shared
            session.start()
        }
    }

    // MARK: - Helpers

    private func calendarRow(
        name: String,
        color: Color,
        isLinked: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)

            Text(name)
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            Button {
                action()
            } label: {
                Text(isLinked ? "Linked" : "Link")
                    .font(AppFonts.bodyMedium(13))
                    .foregroundColor(isLinked ? AppColors.accentWarm : AppColors.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isLinked ? AppColors.accentWarm.opacity(0.1) : AppColors.accentLight)
                    .cornerRadius(8)
            }
            .accessibilityLabel(isLinked ? "Unlink \(name)" : "Link \(name)")
        }
        .padding(.vertical, 4)
    }

    private func isLinked(calendarID: String, source: CalendarSource) -> Bool {
        let links = calendarSyncManager?.linkedCalendars() ?? []
        return links.contains { $0.calendarID == calendarID && $0.source == source.rawValue }
    }

    private func toggleLink(calendar: EKCalendar) {
        let links = calendarSyncManager?.linkedCalendars() ?? []
        if let existing = links.first(where: { $0.calendarID == calendar.calendarIdentifier && $0.source == CalendarSource.apple.rawValue }) {
            calendarSyncManager?.unlinkCalendar(existing)
        } else {
            let components = calendar.cgColor.components ?? [0, 0.3, 0.1, 1]
            let hex = String(format: "#%02X%02X%02X",
                             Int((components[safe: 0] ?? 0) * 255),
                             Int((components[safe: 1] ?? 0) * 255),
                             Int((components[safe: 2] ?? 0) * 255))
            calendarSyncManager?.linkCalendar(
                source: .apple,
                calendarID: calendar.calendarIdentifier,
                name: calendar.title,
                color: hex
            )
        }
    }

    private func toggleReminderLink(list: EKCalendar) {
        let links = calendarSyncManager?.linkedCalendars() ?? []
        if let existing = links.first(where: { $0.calendarID == list.calendarIdentifier && $0.source == CalendarSource.reminders.rawValue }) {
            calendarSyncManager?.unlinkCalendar(existing)
        } else {
            let components = list.cgColor.components ?? [0, 0.3, 0.1, 1]
            let hex = String(format: "#%02X%02X%02X",
                             Int((components[safe: 0] ?? 0) * 255),
                             Int((components[safe: 1] ?? 0) * 255),
                             Int((components[safe: 2] ?? 0) * 255))
            calendarSyncManager?.linkCalendar(
                source: .reminders,
                calendarID: list.calendarIdentifier,
                name: list.title,
                color: hex
            )
        }
    }

    private func toggleGoogleLink(calendar: GoogleCalendar) {
        let links = calendarSyncManager?.linkedCalendars() ?? []
        if let existing = links.first(where: { $0.calendarID == calendar.id && $0.source == CalendarSource.google.rawValue }) {
            calendarSyncManager?.unlinkCalendar(existing)
        } else {
            calendarSyncManager?.linkCalendar(
                source: .google,
                calendarID: calendar.id,
                name: calendar.displayName,
                color: calendar.backgroundColor ?? "#4285F4"
            )
        }
    }
}

// MARK: - Google Auth Presentation Context

final class GoogleAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleAuthPresenter()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
