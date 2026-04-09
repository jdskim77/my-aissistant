import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.subscriptionTier) private var tier
    @Environment(\.modelContext) private var modelContext
    @Environment(\.keychainService) private var keychainService
    @State private var appeared = false
    @State private var exportItem: ExportItem?
    private struct ExportItem: Identifiable { let id = UUID(); let url: URL }
    @State private var versionTapCount = 0
    @State private var showDeveloperModeAlert = false
    @State private var exportError: String?
    @State private var showingImportPicker = false
    @State private var importResult: String?
    @State private var importError: String?
    @State private var showingImportConfirm = false
    @State private var pendingImportURL: URL?

    // Account state
    @State private var isSignedIn = false
    @State private var showingSignOutConfirm = false
    @State private var showingDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var accountActionError: String?

    // Developer-only reset state
    @State private var showingResetOnboardingConfirm = false
    @State private var showingWipeDataConfirm = false
    @State private var showingDevResetResultAlert = false
    @State private var devResetResultMessage = ""

    var body: some View {
        NavigationStack {
            List {
                // Appearance
                Section {
                    NavigationLink {
                        ThemePickerView()
                    } label: {
                        settingsRow(
                            icon: "paintpalette.fill",
                            color: AppColors.skyBlue,
                            title: "Appearance",
                            subtitle: ThemeManager.shared.selectedTheme.rawValue
                        )
                    }

                    if AppConstants.isDeveloperToolsEnabled {
                        NavigationLink {
                            AppIconPreviewGallery()
                        } label: {
                            settingsRow(
                                icon: "app.badge.fill",
                                color: AppColors.accent,
                                title: "App Icon Preview",
                                subtitle: "Re-export refined icon"
                            )
                        }
                    }

                    NavigationLink {
                        TextSizeSettingsView()
                    } label: {
                        settingsRow(
                            icon: "textformat.size",
                            color: AppColors.gold,
                            title: "Text Size",
                            subtitle: TextSizeManager.shared.selectedSize.rawValue
                        )
                    }
                } header: {
                    Text("Appearance")
                }

                // Account & Subscription
                Section {
                    NavigationLink {
                        SubscriptionView()
                    } label: {
                        settingsRow(
                            icon: "crown.fill",
                            color: AppColors.accentWarm,
                            title: "Subscription",
                            subtitle: tier.displayName
                        )
                    }

                    NavigationLink {
                        APIKeySettingsView()
                    } label: {
                        settingsRow(
                            icon: "key.fill",
                            color: AppColors.accent,
                            title: "API Keys",
                            subtitle: "Manage your API keys"
                        )
                    }

                    if isSignedIn {
                        Button {
                            Haptics.light()
                            showingSignOutConfirm = true
                        } label: {
                            settingsRow(
                                icon: "rectangle.portrait.and.arrow.right",
                                color: AppColors.textMuted,
                                title: "Sign Out",
                                subtitle: "Stay signed in on other devices"
                            )
                        }

                        Button {
                            Haptics.medium()
                            showingDeleteAccountConfirm = true
                        } label: {
                            settingsRow(
                                icon: "trash.fill",
                                color: AppColors.coral,
                                title: "Delete Account",
                                subtitle: "Permanently delete your account & data"
                            )
                        }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    if isSignedIn {
                        Text("Deleting your account permanently removes your account, all chat history, tasks, check-ins, habits, and goals. This cannot be undone.")
                    }
                }

                // App Settings
                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        settingsRow(
                            icon: "bell.fill",
                            color: AppColors.coral,
                            title: "Notifications",
                            subtitle: "Check-in reminders & alerts"
                        )
                    }

                    NavigationLink {
                        CheckInPreferencesView()
                    } label: {
                        settingsRow(
                            icon: "clock.badge.checkmark.fill",
                            color: AppColors.accent,
                            title: "Check-in Schedule",
                            subtitle: "Windows, timing & insights"
                        )
                    }

                    NavigationLink {
                        VoiceSettingsView()
                    } label: {
                        settingsRow(
                            icon: "waveform.circle.fill",
                            color: AppColors.accentWarm,
                            title: "Voice",
                            subtitle: "Voice mode & voice selection"
                        )
                    }

                    NavigationLink {
                        CalendarSettingsView()
                    } label: {
                        settingsRow(
                            icon: "calendar",
                            color: AppColors.accent,
                            title: "Calendar",
                            subtitle: "Manage calendar connections"
                        )
                    }

                    NavigationLink {
                        HabitsView()
                    } label: {
                        settingsRow(
                            icon: "leaf.fill",
                            color: AppColors.completionGreen,
                            title: "Habits",
                            subtitle: "Track daily habits & streaks"
                        )
                    }
                } header: {
                    Text("Preferences")
                }

                // Permissions
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Label("Manage Permissions", systemImage: "lock.shield")
                                .font(AppFonts.body(15))
                                .foregroundColor(AppColors.textPrimary)
                            Spacer()
                            Text("Mic, Calendar, Notifications")
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.textMuted)
                            Image(systemName: "arrow.up.right")
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.textMuted)
                        }
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    Text("Opens iOS Settings to manage microphone, calendar, notification, and camera access.")
                }

                // Backup & Restore
                Section {
                    Button {
                        Haptics.light()
                        do {
                            let service = DataExportService(modelContext: modelContext)
                            let url = try service.exportFileURL()
                            exportItem = ExportItem(url: url)
                        } catch {
                            exportError = error.localizedDescription
                        }
                    } label: {
                        settingsRow(
                            icon: "square.and.arrow.up",
                            color: AppColors.completionGreen,
                            title: "Back Up Data",
                            subtitle: "Save all tasks, check-ins & chats"
                        )
                    }

                    Button {
                        Haptics.light()
                        showingImportPicker = true
                    } label: {
                        settingsRow(
                            icon: "square.and.arrow.down",
                            color: AppColors.skyBlue,
                            title: "Restore from Backup",
                            subtitle: "Import a previous backup file"
                        )
                    }

                    if let result = importResult {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColors.completionGreen)
                            Text(result)
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.completionGreen)
                        }
                    }

                    if let error = importError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppColors.coral)
                            Text(error)
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.coral)
                        }
                    }

                    if let error = exportError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppColors.coral)
                            Text(error)
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.coral)
                        }
                    }
                } header: {
                    Text("Backup & Restore")
                } footer: {
                    Text("Back up your data to a file you can save to iCloud Drive, email, or AirDrop. Restore it on any device.")
                }

                // Legal
                Section {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        settingsRow(
                            icon: "hand.raised.fill",
                            color: AppColors.skyBlue,
                            title: "Privacy Policy",
                            subtitle: "How your data is handled"
                        )
                    }

                    NavigationLink {
                        TermsOfServiceView()
                    } label: {
                        settingsRow(
                            icon: "doc.text.fill",
                            color: AppColors.textMuted,
                            title: "Terms of Service",
                            subtitle: "Usage terms and conditions"
                        )
                    }
                } header: {
                    Text("Legal")
                }

                // About
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Our Vision")
                            .font(AppFonts.label(13))
                            .foregroundColor(AppColors.accent)
                        Text("Find balance across the four dimensions that matter most — physical, mental, emotional, and spiritual well-being. Thrivn turns daily check-ins, habit tracking, and a context-aware AI assistant into one place to see your week clearly and act on what matters.")
                            .font(AppFonts.body(14))
                            .foregroundColor(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)

                    Button {
                        versionTapCount += 1
                        if versionTapCount >= 7 {
                            versionTapCount = 0
                            // Read/write the raw flag directly so the toggle isn't
                            // poisoned by isBetaUnlimited returning true unconditionally.
                            let current = AppConstants.isDeveloperToolsEnabled
                            UserDefaults.standard.set(!current, forKey: AppConstants.developerModeKey)
                            showDeveloperModeAlert = true
                        }
                    } label: {
                        HStack {
                            Text("Version")
                                .font(AppFonts.body(15))
                                .foregroundColor(AppColors.textPrimary)
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                                .font(AppFonts.body(15))
                                .foregroundColor(AppColors.textMuted)
                        }
                    }
                    .buttonStyle(.plain)

                    if AppConstants.isBetaUnlimited {
                        HStack(spacing: 10) {
                            Image(systemName: "testtube.2")
                                .foregroundColor(AppColors.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Beta Tester")
                                    .font(AppFonts.bodyMedium(15))
                                    .foregroundColor(AppColors.textPrimary)
                                Text("All limits removed during beta")
                                    .font(AppFonts.caption(12))
                                    .foregroundColor(AppColors.textMuted)
                            }
                            Spacer()
                            Text("BETA")
                                .font(AppFonts.label(11))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppColors.accent)
                                .cornerRadius(6)
                        }
                    }

                    // Send Feedback — opens Google Form during beta, Mail during public
                    Button {
                        Haptics.light()
                        sendFeedback()
                    } label: {
                        settingsRow(
                            icon: "bubble.left.and.bubble.right.fill",
                            color: AppColors.accent,
                            title: "Send Feedback",
                            subtitle: AppConstants.isBetaUnlimited
                                ? "Anonymous form — ~5 min, every answer shapes what comes next"
                                : "Report a bug or share an idea"
                        )
                    }
                    .buttonStyle(.plain)

                    if AppConstants.isDeveloperToolsEnabled {
                        HStack {
                            Image(systemName: "hammer.fill")
                                .foregroundColor(AppColors.accentWarm)
                            Text("Developer Mode")
                                .font(AppFonts.body(15))
                                .foregroundColor(AppColors.accentWarm)
                            Spacer()
                            Text("Active")
                                .font(AppFonts.caption(13))
                                .foregroundColor(AppColors.accentWarm)
                        }
                    }
                } header: {
                    Text("About")
                }

                // Developer Tools — only visible when the user explicitly enabled
                // developer mode (NOT for all beta testers, since the section
                // contains destructive Wipe All Data action).
                if AppConstants.isDeveloperToolsEnabled {
                    Section {
                        Button {
                            Haptics.light()
                            showingResetOnboardingConfirm = true
                        } label: {
                            settingsRow(
                                icon: "arrow.counterclockwise",
                                color: AppColors.accentWarm,
                                title: "Replay Onboarding",
                                subtitle: "Re-run the FTUE flow (keeps your data)"
                            )
                        }

                        Button {
                            Haptics.light()
                            showingWipeDataConfirm = true
                        } label: {
                            settingsRow(
                                icon: "trash.fill",
                                color: AppColors.coral,
                                title: "Wipe All App Data",
                                subtitle: "Delete everything and re-run onboarding"
                            )
                        }
                    } header: {
                        Text("Developer Tools")
                    } footer: {
                        Text("These actions only appear in developer mode. \"Wipe All App Data\" is destructive and cannot be undone — it deletes tasks, check-ins, chats, goals, and patterns from this device. iCloud will sync the deletes to other devices.")
                    }
                }
            }
            .alert("Developer Mode", isPresented: $showDeveloperModeAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(AppConstants.isDeveloperToolsEnabled ? "Developer mode enabled. Usage limits bypassed." : "Developer mode disabled.")
            }
            .confirmationDialog(
                "Replay Onboarding?",
                isPresented: $showingResetOnboardingConfirm,
                titleVisibility: .visible
            ) {
                Button("Replay") { performResetOnboarding() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will reset your onboarding flag so the FTUE flow runs again on next launch. Your tasks, check-ins, chats, and goals are kept.")
            }
            .confirmationDialog(
                "Wipe ALL App Data?",
                isPresented: $showingWipeDataConfirm,
                titleVisibility: .visible
            ) {
                Button("Wipe Everything", role: .destructive) { performWipeAllData() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently deletes every task, check-in, chat message, season goal, habit, focus session, pattern, and your profile from this device. iCloud will sync the deletes to other devices. Onboarding will run again on next launch. This cannot be undone.")
            }
            .alert("Done", isPresented: $showingDevResetResultAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(devResetResultMessage)
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .offset(y: appeared ? 0 : 10)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    appeared = true
                }
                refreshSignInState()
            }
            .confirmationDialog(
                "Sign out of Thrivn?",
                isPresented: $showingSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign Out") {
                    Task { await performSignOut() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your data on this device stays put. You can sign back in any time to resume syncing.")
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $showingDeleteAccountConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task { await performDeleteAccount() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently deletes your Thrivn account on the server and wipes every task, check-in, chat, habit, and goal from this device. iCloud will sync the deletes to your other devices. This cannot be undone.")
            }
            .alert("Account", isPresented: .init(
                get: { accountActionError != nil },
                set: { if !$0 { accountActionError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(accountActionError ?? "")
            }
            .overlay {
                if isDeletingAccount {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text("Deleting account…")
                                .font(AppFonts.body(14))
                                .foregroundColor(.white)
                        }
                        .padding(24)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                    }
                }
            }
            .sheet(item: $exportItem) { item in
                ShareSheet(items: [item.url])
            }
            .alert("Export Failed", isPresented: .init(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(exportError ?? "")
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    pendingImportURL = url
                    showingImportConfirm = true
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .confirmationDialog("Restore from Backup?", isPresented: $showingImportConfirm, titleVisibility: .visible) {
                Button("Restore") {
                    performImport()
                }
                Button("Cancel", role: .cancel) {
                    pendingImportURL = nil
                }
            } message: {
                Text("This will add any data from the backup that doesn't already exist on this device. Your current data will not be deleted.")
            }
        }
    }

    private func performImport() {
        guard let url = pendingImportURL else { return }
        defer { pendingImportURL = nil }

        // Start accessing security-scoped resource (from file picker)
        guard url.startAccessingSecurityScopedResource() else {
            importError = "Couldn't access the selected file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let service = DataExportService(modelContext: modelContext)
            let result = try service.importJSON(from: url)
            Haptics.success()
            importResult = result.summary
            importError = nil
            // Auto-clear success message after 8 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                importResult = nil
            }
        } catch {
            Haptics.medium()
            importError = error.localizedDescription
            importResult = nil
        }
    }

    // MARK: - Account Actions

    /// Open the right feedback channel for the current build phase.
    /// - Beta (`isBetaUnlimited == true`): opens the structured Google Form in Safari.
    ///   Anonymous, ~5 min, designed for high-signal beta feedback.
    /// - Public: opens the system Mail composer pre-filled with device, OS, and
    ///   app version diagnostics so support can debug without asking.
    private func sendFeedback() {
        if AppConstants.isBetaUnlimited {
            if let url = URL(string: AppConstants.feedbackGoogleFormURL) {
                UIApplication.shared.open(url)
            }
            return
        }

        // Public path: mailto with diagnostic context pre-filled.
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current.model
        let osVersion = UIDevice.current.systemVersion

        let subject = "Thrivn Feedback (v\(appVersion))"
        let body = """


        ---
        Please describe the issue or idea above this line.

        Diagnostics (helps us debug — feel free to remove):
        • App: \(appVersion) (\(buildNumber))
        • Device: \(device)
        • iOS: \(osVersion)
        """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppConstants.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }

    /// Refresh the local sign-in indicator. Reads from the Keychain so it
    /// reflects the actual stored refresh-token state, not a stale flag.
    private func refreshSignInState() {
        let refresh = keychainService.read(key: AppConstants.thrivnRefreshTokenKey) ?? ""
        isSignedIn = !refresh.isEmpty
    }

    /// Sign out without deleting any local data. Clears the backend session
    /// and the local tokens; tasks/check-ins/chats remain on the device.
    private func performSignOut() async {
        let backend = ThrivnBackendService(keychain: keychainService)
        await backend.signOut()
        await MainActor.run {
            refreshSignInState()
            Haptics.success()
        }
    }

    /// Permanently delete the user's account. Order matters: clear local data
    /// FIRST so even if the backend or network fails, the user is fully wiped
    /// from the device. Backend deletion is best-effort.
    private func performDeleteAccount() async {
        await MainActor.run {
            isDeletingAccount = true
        }
        defer {
            Task { @MainActor in
                isDeletingAccount = false
            }
        }

        // 1. Wipe local SwiftData. This is the part Apple cares most about
        //    for compliance — the on-device record must be gone.
        var localWipeError: String?
        do {
            try wipeAllLocalData()
        } catch {
            localWipeError = error.localizedDescription
        }

        // 2. Tell the backend to delete the account. Best-effort: if the
        //    network call fails or the endpoint isn't shipped yet, the local
        //    wipe still stands and the user is signed out.
        let backend = ThrivnBackendService(keychain: keychainService)
        await backend.deleteAccount()

        // 3. Clear remaining BYOK / OAuth credentials so the next launch
        //    behaves like a fresh install.
        keychainService.delete(key: AppConstants.anthropicAPIKeyKey)
        keychainService.delete(key: AppConstants.openAIAPIKeyKey)
        keychainService.delete(key: AppConstants.googleAccessTokenKey)
        keychainService.delete(key: AppConstants.googleRefreshTokenKey)
        keychainService.delete(key: AppConstants.googleTokenExpiryKey)

        await MainActor.run {
            refreshSignInState()
            if let err = localWipeError {
                accountActionError = "Account signed out and backend asked to delete, but local data wipe failed: \(err). Please reinstall the app to fully clean up."
            } else {
                Haptics.success()
                accountActionError = "Your account has been deleted. Force-quit the app and reopen for a fresh start."
            }
        }
    }

    /// Wipes every row from every @Model + clears onboarding-related
    /// UserDefaults. Throws if any individual delete or save fails.
    private func wipeAllLocalData() throws {
        _ = try wipe(TaskItem.self)
        _ = try wipe(ChatMessage.self)
        _ = try wipe(CheckInRecord.self)
        _ = try wipe(DailyBalanceCheckIn.self)
        _ = try wipe(DailySnapshot.self)
        _ = try wipe(SeasonGoal.self)
        _ = try wipe(HabitItem.self)
        _ = try wipe(FocusSession.self)
        _ = try wipe(ActivityEntry.self)
        _ = try wipe(ActivityPattern.self)
        _ = try wipe(AlarmEntry.self)
        _ = try wipe(CalendarLink.self)
        _ = try wipe(UsageTracker.self)
        _ = try wipe(UserDimensionPreference.self)
        _ = try wipe(UserProfile.self)
        try modelContext.save()

        let keysToReset = [
            "compassCoachMarksSeen",
            "didMigrateVoiceModeDefault_v1",
            "thrivn.usageTracker.deviceID",
            AppConstants.lastGreetedTimestampKey,
            AppConstants.lastGreetingTextKey
        ]
        for key in keysToReset {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Developer Reset Actions

    /// Flips the onboarding flag to false. Keeps all data intact. The user
    /// will see the FTUE flow on next app cold-launch (or by force-quitting
    /// and reopening). Use this for fast iteration on onboarding copy/UX
    /// without losing your test data.
    private func performResetOnboarding() {
        do {
            let descriptor = FetchDescriptor<UserProfile>()
            if let profile = try modelContext.fetch(descriptor).first {
                profile.onboardingCompleted = false
            }
            // Reset coach-marks first-launch flag too so the Compass coach
            // marks reappear during the redesign test.
            UserDefaults.standard.removeObject(forKey: "compassCoachMarksSeen")

            try modelContext.save()
            Haptics.success()
            devResetResultMessage = "Onboarding flag reset. Force-quit the app and reopen to see the FTUE flow."
            showingDevResetResultAlert = true
        } catch {
            Haptics.medium()
            devResetResultMessage = "Failed to reset onboarding: \(error.localizedDescription)"
            showingDevResetResultAlert = true
        }
    }

    /// Wipes every row from every @Model in the SwiftData store. Resets
    /// onboarding-related UserDefaults. iCloud will sync the deletes.
    /// Does NOT touch Keychain (your API key stays put).
    private func performWipeAllData() {
        var deletedCount = 0
        do {
            // SwiftData has no "drop everything" — fetch each model type and delete row-by-row.
            // Order chosen so child rows go before parent rows where relationships exist.
            deletedCount += try wipe(TaskItem.self)
            deletedCount += try wipe(ChatMessage.self)
            deletedCount += try wipe(CheckInRecord.self)
            deletedCount += try wipe(DailyBalanceCheckIn.self)
            deletedCount += try wipe(DailySnapshot.self)
            deletedCount += try wipe(SeasonGoal.self)
            deletedCount += try wipe(HabitItem.self)
            deletedCount += try wipe(FocusSession.self)
            deletedCount += try wipe(ActivityEntry.self)
            deletedCount += try wipe(ActivityPattern.self)
            deletedCount += try wipe(AlarmEntry.self)
            deletedCount += try wipe(CalendarLink.self)
            deletedCount += try wipe(UsageTracker.self)
            deletedCount += try wipe(UserDimensionPreference.self)
            deletedCount += try wipe(UserProfile.self)

            try modelContext.save()

            // Reset relevant UserDefaults flags so the next launch behaves like a fresh install.
            let keysToReset = [
                "compassCoachMarksSeen",
                "didMigrateVoiceModeDefault_v1",
                AppConstants.lastGreetedTimestampKey,
                AppConstants.lastGreetingTextKey
            ]
            for key in keysToReset {
                UserDefaults.standard.removeObject(forKey: key)
            }

            Haptics.success()
            devResetResultMessage = "Wiped \(deletedCount) records. Force-quit the app and reopen to see the FTUE flow with a clean state."
            showingDevResetResultAlert = true
        } catch {
            Haptics.medium()
            devResetResultMessage = "Wipe failed after \(deletedCount) deletes: \(error.localizedDescription)"
            showingDevResetResultAlert = true
        }
    }

    /// Helper: fetch every row of `T` and delete each. Returns the count.
    private func wipe<T: PersistentModel>(_ type: T.Type) throws -> Int {
        let descriptor = FetchDescriptor<T>()
        let rows = try modelContext.fetch(descriptor)
        for row in rows {
            modelContext.delete(row)
        }
        return rows.count
    }

    private struct ShareSheet: UIViewControllerRepresentable {
        let items: [Any]
        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: items, applicationActivities: nil)
        }
        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    }

    private func settingsRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(AppFonts.bodyMedium(16))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(AppColors.textPrimary)
                Text(subtitle)
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)
            }
        }
        .padding(.vertical, 2)
    }
}
