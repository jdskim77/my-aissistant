import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.subscriptionTier) private var tier
    @Environment(\.modelContext) private var modelContext
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

                    // TEMP: App Icon Preview (for re-exporting the refined icon)
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
                } header: {
                    Text("Account")
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
                        Text("Excel at life by finding balance. Thrivn reveals where you're thriving and where you need attention — across your physical, mental, emotional, and spiritual well-being. Through daily check-ins, habit tracking, and an AI coach that understands your goals, it helps you align how you spend your time with what truly matters.")
                            .font(AppFonts.body(14))
                            .foregroundColor(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)

                    Button {
                        versionTapCount += 1
                        if versionTapCount >= 7 {
                            versionTapCount = 0
                            let current = AppConstants.isDeveloperMode
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

                    if AppConstants.isDeveloperMode && !AppConstants.isBetaUnlimited {
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

                // Developer Tools — only visible in developer mode
                if AppConstants.isDeveloperMode {
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
                Text(AppConstants.isDeveloperMode ? "Developer mode enabled. Usage limits bypassed." : "Developer mode disabled.")
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
