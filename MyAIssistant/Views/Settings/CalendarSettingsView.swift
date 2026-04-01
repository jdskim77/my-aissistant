import SwiftUI
import AuthenticationServices

struct CalendarSettingsView: View {
    @Environment(\.calendarSyncManager) private var calendarSyncManager
    @State private var showingImport = false
    @State private var googleClientID: String = {
        let stored = UserDefaults.standard.string(forKey: AppConstants.googleClientIDKey) ?? ""
        return stored.isEmpty ? AppConstants.googleClientID : stored
    }()
    @State private var showClientID = false
    @State private var clientIDSaved = false
    @State private var isGoogleConnected = false
    @State private var isSigningInGoogle = false
    @State private var googleAuthError: String?
    @State private var showingGoogleSignOutConfirm = false
    @State private var showingGoogleDisconnectConfirm = false
    @State private var syncResult: SyncResult?
    @State private var syncStartTime: Date?

    private enum SyncResult: Equatable {
        case success(String)
        case error(String)
    }

    var body: some View {
        List {
            // Connection status
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "calendar")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.accent)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Calendar")
                            .font(AppFonts.bodyMedium(15))
                            .foregroundColor(AppColors.textPrimary)
                        Text(calendarSyncManager?.appleCalendarAuthorized == true ? "Connected" : "Not connected")
                            .font(AppFonts.caption(13))
                            .foregroundColor(calendarSyncManager?.appleCalendarAuthorized == true ? AppColors.accentWarm : AppColors.textMuted)
                    }

                    Spacer()

                    if calendarSyncManager?.appleCalendarAuthorized == true {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.accentWarm)
                    }
                }

                HStack(spacing: 14) {
                    Image(systemName: "globe")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.coral)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Google Calendar")
                            .font(AppFonts.bodyMedium(15))
                            .foregroundColor(AppColors.textPrimary)
                        Text(googleStatusText)
                            .font(AppFonts.caption(13))
                            .foregroundColor(isGoogleConnected ? AppColors.accentWarm : (googleClientID.isEmpty ? AppColors.textMuted : AppColors.accentWarm))
                    }

                    Spacer()

                    if isGoogleConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.accentWarm)
                    } else if !googleClientID.isEmpty {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(AppColors.textMuted)
                    }
                }
            } header: {
                Text("Calendar Sources")
            }

            // Google Client ID
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Google OAuth Client ID")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textPrimary)

                    HStack {
                        if showClientID {
                            TextField("123456789.apps.googleusercontent.com", text: $googleClientID)
                                .font(AppFonts.body(13))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("123456789.apps.googleusercontent.com", text: $googleClientID)
                                .font(AppFonts.body(13))
                        }

                        Button {
                            showClientID.toggle()
                        } label: {
                            Image(systemName: showClientID ? "eye.slash" : "eye")
                                .font(.system(size: 14))
                                .foregroundColor(AppColors.textMuted)
                        }
                    }
                    .padding(12)
                    .background(AppColors.surface)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppColors.border, lineWidth: 1)
                    )

                    Button {
                        let trimmed = googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
                        googleClientID = trimmed
                        calendarSyncManager?.setGoogleClientID(trimmed)
                        clientIDSaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { clientIDSaved = false }
                    } label: {
                        Text("Save Client ID")
                            .font(AppFonts.bodyMedium(14))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppColors.accent)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    if clientIDSaved {
                        Text("Client ID saved")
                            .font(AppFonts.caption(12))
                            .foregroundColor(AppColors.accentWarm)
                    }

                    // Google Sign-In / Sign-Out
                    if !googleClientID.isEmpty {
                        Divider()
                            .padding(.vertical, 4)

                        if isGoogleConnected {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AppColors.accentWarm)
                                Text("Signed in to Google")
                                    .font(AppFonts.bodyMedium(14))
                                    .foregroundColor(AppColors.accentWarm)
                                Spacer()
                                Button {
                                    showingGoogleSignOutConfirm = true
                                } label: {
                                    Text("Sign Out")
                                        .font(AppFonts.bodyMedium(13))
                                        .foregroundColor(AppColors.coral)
                                }
                            }
                        } else {
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
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    Text("Sign in with Google")
                                        .font(AppFonts.bodyMedium(14))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(hex: "4285F4"))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .disabled(isSigningInGoogle)
                        }
                    }
                }
            } header: {
                Text("Google Calendar Setup")
            } footer: {
                Text("Create an OAuth client ID in Google Cloud Console with Calendar API enabled. Use iOS type with bundle ID com.myaissistant. Add your email as a test user in the OAuth consent screen.")
                    .font(AppFonts.caption(11))
            }

            // Linked calendars
            Section {
                let links = calendarSyncManager?.linkedCalendars() ?? []
                if links.isEmpty {
                    Text("No calendars linked. Tap 'Manage Calendars' to get started.")
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.textMuted)
                } else {
                    ForEach(links, id: \.id) { link in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: link.color))
                                .frame(width: 10, height: 10)

                            Text(link.name)
                                .font(AppFonts.body(14))
                                .foregroundColor(AppColors.textPrimary)

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { link.enabled },
                                set: { _ in calendarSyncManager?.toggleCalendarLink(link) }
                            ))
                            .labelsHidden()
                            .tint(AppColors.accent)
                        }
                    }
                }
            } header: {
                Text("Linked Calendars")
            }

            // Actions
            Section {
                Button {
                    showingImport = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle")
                            .foregroundColor(AppColors.accent)
                        Text("Manage Calendars")
                            .font(AppFonts.bodyMedium(15))
                            .foregroundColor(AppColors.accent)
                    }
                }

                Button {
                    Task { await performSync() }
                } label: {
                    HStack(spacing: 10) {
                        if calendarSyncManager?.isSyncing == true {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(AppColors.accent)
                        }
                        Text(calendarSyncManager?.isSyncing == true ? "Syncing…" : "Sync Now")
                            .font(AppFonts.bodyMedium(15))
                            .foregroundColor(AppColors.accent)
                    }
                }
                .disabled(calendarSyncManager?.isSyncing == true)

                if let syncResult {
                    HStack(spacing: 8) {
                        switch syncResult {
                        case .success(let message):
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColors.accentWarm)
                            Text(message)
                                .font(AppFonts.caption(13))
                                .foregroundColor(AppColors.accentWarm)
                        case .error(let message):
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppColors.coral)
                            Text(message)
                                .font(AppFonts.caption(13))
                                .foregroundColor(AppColors.coral)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } header: {
                Text("Actions")
            }

            // Disconnect Google
            if isGoogleConnected || !googleClientID.isEmpty {
                Section {
                    Button(role: .destructive) {
                        showingGoogleDisconnectConfirm = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(AppColors.coral)
                            Text("Disconnect Google Calendar")
                                .font(AppFonts.bodyMedium(15))
                                .foregroundColor(AppColors.coral)
                        }
                    }
                } footer: {
                    Text("Signs out, removes linked Google calendars, and clears your Client ID. Synced events already in the app are kept.")
                        .font(AppFonts.caption(11))
                }
            }

            // Info
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How Calendar Sync Works")
                        .font(AppFonts.bodyMedium(14))
                        .foregroundColor(AppColors.textPrimary)
                    Text("Events from linked calendars appear as tasks in your schedule. Tasks created in the app can be pushed to Apple or Google Calendar. Your AI assistant can also add and remove events on your behalf.")
                        .font(AppFonts.body(13))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Calendar Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingImport) {
            CalendarImportView()
        }
        .onAppear {
            Task {
                isGoogleConnected = await calendarSyncManager?.googleCalendarConnected() == true
            }
        }
        .alert("Sign Out of Google?", isPresented: $showingGoogleSignOutConfirm) {
            Button("Sign Out", role: .destructive) {
                Task {
                    await calendarSyncManager?.googleService.signOut()
                    isGoogleConnected = false
                    calendarSyncManager?.googleCalendars = []
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Google Calendar events will no longer sync.")
        }
        .alert("Disconnect Google Calendar?", isPresented: $showingGoogleDisconnectConfirm) {
            Button("Disconnect", role: .destructive) {
                Task { await disconnectGoogle() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will sign out, remove all linked Google calendars, and clear your Client ID. Events already synced to your schedule will be kept.")
        }
    }

    // MARK: - Sync

    private func performSync() async {
        guard let syncManager = calendarSyncManager else { return }

        syncResult = nil
        Haptics.light()

        let enabledCount = syncManager.enabledCalendarLinks().count
        guard enabledCount > 0 else {
            syncResult = .error("No calendars linked — tap Manage Calendars first")
            Haptics.medium()
            autoClearSyncResult()
            return
        }

        await syncManager.syncAll()

        if let error = syncManager.lastError {
            syncResult = .error("Sync failed: \(error)")
            Haptics.medium()
        } else {
            let plural = enabledCount == 1 ? "calendar" : "calendars"
            syncResult = .success("Synced \(enabledCount) \(plural) just now")
            Haptics.success()
        }

        withAnimation(.snappy(duration: 0.25)) {}
        autoClearSyncResult()
    }

    private func autoClearSyncResult() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation(.smooth(duration: 0.3)) {
                syncResult = nil
            }
        }
    }

    // MARK: - Disconnect

    private func disconnectGoogle() async {
        guard let syncManager = calendarSyncManager else { return }

        // Sign out of Google
        await syncManager.googleService.signOut()

        // Remove all linked Google calendars
        let googleLinks = syncManager.linkedCalendars().filter { $0.source == CalendarSource.google.rawValue }
        for link in googleLinks {
            syncManager.unlinkCalendar(link)
        }

        // Clear the stored client ID
        googleClientID = ""
        UserDefaults.standard.removeObject(forKey: AppConstants.googleClientIDKey)
        await syncManager.googleService.updateClientID("")

        // Reset state
        syncManager.googleCalendars = []
        isGoogleConnected = false

        Haptics.success()
    }

    // MARK: - Computed

    private var googleStatusText: String {
        if isGoogleConnected { return "Connected" }
        if !googleClientID.isEmpty { return "Client ID set — sign in below" }
        return "Not configured"
    }

    // MARK: - Google OAuth

    private func signInWithGoogle() {
        guard let syncManager = calendarSyncManager else { return }

        Task {
            guard let authURL = await syncManager.googleService.authorizationURL() else {
                googleAuthError = "Client ID not configured correctly."
                return
            }

            isSigningInGoogle = true
            googleAuthError = nil

            let callbackURL = await startGoogleAuth(url: authURL)

            if let callbackURL,
               let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
               let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                do {
                    try await syncManager.googleService.exchangeCodeForTokens(code)
                    await syncManager.loadGoogleCalendars()
                    isGoogleConnected = true

                    // Auto-link primary calendar so the AI can access it immediately
                    autoLinkPrimaryCalendar()

                    // Trigger initial sync
                    await syncManager.syncGoogleCalendar()
                } catch {
                    googleAuthError = "Sign-in failed: \(error.localizedDescription)"
                }
            } else {
                googleAuthError = "Sign-in was cancelled."
            }

            isSigningInGoogle = false
        }
    }

    private func autoLinkPrimaryCalendar() {
        guard let syncManager = calendarSyncManager else { return }
        let calendars = syncManager.googleCalendars

        // Find the primary calendar, or fall back to the first one
        let primary = calendars.first(where: { $0.primary == true }) ?? calendars.first
        guard let cal = primary else { return }

        // Only link if not already linked
        let existing = syncManager.linkedCalendars()
        if !existing.contains(where: { $0.calendarID == cal.id && $0.source == CalendarSource.google.rawValue }) {
            syncManager.linkCalendar(
                source: .google,
                calendarID: cal.id,
                name: cal.displayName,
                color: cal.backgroundColor ?? "#4285F4"
            )
        }
    }

    @MainActor
    private func startGoogleAuth(url: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "com.myaissistant"
            ) { callbackURL, error in
                if error != nil {
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
}
