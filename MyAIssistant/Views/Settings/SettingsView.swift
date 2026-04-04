import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.subscriptionTier) private var tier
    @Environment(\.modelContext) private var modelContext
    @State private var appeared = false
    @State private var exportURL: URL?
    @State private var showingExportShare = false
    @State private var exportError: String?
    @State private var showingImportPicker = false
    @State private var importResult: String?
    @State private var importError: String?
    @State private var showingImportConfirm = false
    @State private var pendingImportURL: URL?

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
                            exportURL = try service.exportFileURL()
                            showingExportShare = true
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
                    HStack {
                        Text("Version")
                            .font(AppFonts.body(15))
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .font(AppFonts.body(15))
                            .foregroundColor(AppColors.textMuted)
                    }
                } header: {
                    Text("About")
                }
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
            .sheet(isPresented: $showingExportShare) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
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
