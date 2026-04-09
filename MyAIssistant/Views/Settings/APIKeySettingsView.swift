import SwiftUI

struct APIKeySettingsView: View {
    @Environment(\.keychainService) private var keychainService
    @State private var anthropicKey = ""
    @State private var openAIKey = ""
    @State private var showAnthropicKey = false
    @State private var showOpenAIKey = false
    @State private var saveStatus: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Anthropic API Key")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textPrimary)

                    HStack {
                        if showAnthropicKey {
                            TextField("sk-ant-...", text: $anthropicKey)
                                .font(AppFonts.body(14))
                                .textContentType(.password)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("sk-ant-...", text: $anthropicKey)
                                .font(AppFonts.body(14))
                                .textContentType(.password)
                        }

                        Button {
                            showAnthropicKey.toggle()
                        } label: {
                            Image(systemName: showAnthropicKey ? "eye.slash" : "eye")
                                .font(AppFonts.body(14))
                                .foregroundColor(AppColors.textMuted)
                        }
                        .accessibilityLabel(showAnthropicKey ? "Hide API key" : "Show API key")
                    }
                    .padding(12)
                    .background(AppColors.surface)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppColors.border, lineWidth: 1)
                    )

                    Text("Used for Claude AI chat and check-ins.")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textMuted)
                }
            } header: {
                Text("Claude (Anthropic)")
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("OpenAI API Key")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textPrimary)

                    HStack {
                        if showOpenAIKey {
                            TextField("sk-...", text: $openAIKey)
                                .font(AppFonts.body(14))
                                .textContentType(.password)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("sk-...", text: $openAIKey)
                                .font(AppFonts.body(14))
                                .textContentType(.password)
                        }

                        Button {
                            showOpenAIKey.toggle()
                        } label: {
                            Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                                .font(AppFonts.body(14))
                                .foregroundColor(AppColors.textMuted)
                        }
                        .accessibilityLabel(showOpenAIKey ? "Hide API key" : "Show API key")
                    }
                    .padding(12)
                    .background(AppColors.surface)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppColors.border, lineWidth: 1)
                    )

                    Text("Optional. When set, the app uses your OpenAI key instead of Claude.")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textMuted)
                }
            } header: {
                Text("OpenAI (Optional)")
            }

            Section {
                Button {
                    saveKeys()
                } label: {
                    Text("Save API Keys")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.accent)
                        .cornerRadius(10)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if let saveStatus {
                    Text(saveStatus)
                        .font(AppFonts.caption(12))
                        .foregroundColor(saveStatus.contains("saved") ? AppColors.accentWarm : AppColors.coral)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Security")
                        .font(AppFonts.bodyMedium(14))
                        .foregroundColor(AppColors.textPrimary)
                    Text("API keys are stored securely in your device's Keychain and never leave this device.")
                        .font(AppFonts.body(13))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("API Keys")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadKeys()
        }
    }

    private func loadKeys() {
        anthropicKey = keychainService.anthropicAPIKey() ?? ""
        openAIKey = keychainService.openAIAPIKey() ?? ""
    }

    private func saveKeys() {
        var results: [String] = []

        // Trim whitespace that may have been copied with the key
        anthropicKey = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        openAIKey = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if !anthropicKey.isEmpty {
            if keychainService.saveAnthropicAPIKey(anthropicKey) {
                results.append("Anthropic key saved")
            } else {
                results.append("Failed to save Anthropic key")
            }
        } else {
            _ = keychainService.delete(key: AppConstants.anthropicAPIKeyKey)
        }

        if !openAIKey.isEmpty {
            if keychainService.saveOpenAIAPIKey(openAIKey) {
                results.append("OpenAI key saved")
            } else {
                results.append("Failed to save OpenAI key")
            }
        } else {
            _ = keychainService.delete(key: AppConstants.openAIAPIKeyKey)
        }

        saveStatus = results.isEmpty ? "Keys cleared" : results.joined(separator: ", ")

        // Sync API key to Watch
        WatchSyncManager.shared.syncAPIKey()
    }
}
