import SwiftUI
import AVFoundation

struct VoiceSettingsView: View {
    @AppStorage(AppConstants.voiceModeDefaultKey) private var voiceModeDefault = true
    @AppStorage(AppConstants.selectedVoiceIDKey) private var selectedVoiceID = ""
    @AppStorage(AppConstants.voiceProviderKey) private var voiceProviderRaw = VoiceProviderType.apple.rawValue

    @State private var previewSynthesizer = SpeechSynthesizer()

    private var selectedProvider: VoiceProviderType {
        VoiceProviderType(rawValue: voiceProviderRaw) ?? .apple
    }

    private var voices: [VoiceOption] {
        switch selectedProvider {
        case .apple:
            return AppleVoiceProvider().availableVoices()
        case .edge:
            return EdgeVoiceProvider.edgeVoices
        }
    }

    private var femaleVoices: [VoiceOption] { voices.filter { $0.gender == .female } }
    private var maleVoices: [VoiceOption] { voices.filter { $0.gender == .male } }

    private var accentGroups: [String] {
        Array(Set(voices.map(\.accent))).sorted()
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: $voiceModeDefault) {
                    HStack(spacing: 10) {
                        Image(systemName: "waveform.circle.fill")
                            .foregroundColor(AppColors.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Voice Mode by Default")
                                .font(AppFonts.bodyMedium(15))
                                .foregroundColor(AppColors.textPrimary)
                            Text("Chat opens in voice mode when enabled")
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.textMuted)
                        }
                    }
                }
                .tint(AppColors.accent)
            } header: {
                Text("Preferences")
            }

            Section {
                ForEach(VoiceProviderType.allCases) { provider in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.rawValue)
                                .font(AppFonts.bodyMedium(15))
                                .foregroundColor(AppColors.textPrimary)
                            Text(provider.description)
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.textMuted)
                        }
                        Spacer()
                        if selectedProvider == provider {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(AppColors.accent)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        voiceProviderRaw = provider.rawValue
                        selectedVoiceID = "" // Reset voice when switching provider
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Voice Engine")
            } footer: {
                if selectedProvider == .edge {
                    Text("Edge voices sound more natural but require an internet connection.")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textMuted)
                }
            }

            if selectedProvider == .edge {
                // Group Edge voices by accent
                ForEach(accentGroups, id: \.self) { accent in
                    let accentFemale = femaleVoices.filter { $0.accent == accent }
                    let accentMale = maleVoices.filter { $0.accent == accent }

                    if !accentFemale.isEmpty {
                        Section {
                            ForEach(accentFemale) { voice in
                                voiceRow(voice)
                            }
                        } header: {
                            Text("\(accent) — Female")
                        }
                    }

                    if !accentMale.isEmpty {
                        Section {
                            ForEach(accentMale) { voice in
                                voiceRow(voice)
                            }
                        } header: {
                            Text("\(accent) — Male")
                        }
                    }
                }
            } else {
                Section {
                    ForEach(femaleVoices) { voice in
                        voiceRow(voice)
                    }
                } header: {
                    Text("Female Voices")
                }

                Section {
                    ForEach(maleVoices) { voice in
                        voiceRow(voice)
                    }
                } header: {
                    Text("Male Voices")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            previewSynthesizer.stop()
        }
    }

    private func voiceRow(_ voice: VoiceOption) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.name)
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(AppColors.textPrimary)
                HStack(spacing: 6) {
                    Text(qualityLabel(voice.quality))
                        .font(AppFonts.caption(12))
                        .foregroundColor(voice.quality == .premium ? AppColors.gold :
                                         voice.quality == .enhanced ? AppColors.accent :
                                         AppColors.textMuted)
                    if selectedProvider == .edge {
                        Text("· \(voice.accent)")
                            .font(AppFonts.caption(12))
                            .foregroundColor(AppColors.textMuted)
                    }
                }
            }

            Spacer()

            Button {
                previewVoice(voice)
            } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 22))
                    .foregroundColor(AppColors.accent)
            }
            .buttonStyle(.plain)

            if selectedVoiceID == voice.id {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(AppColors.accent)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedVoiceID = voice.id
        }
        .padding(.vertical, 2)
    }

    private func qualityLabel(_ quality: VoiceOption.VoiceQuality) -> String {
        switch quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        case .standard: return "Default"
        }
    }

    private func previewVoice(_ voice: VoiceOption) {
        previewSynthesizer.stop()
        previewSynthesizer.selectedProviderType = selectedProvider
        previewSynthesizer.selectedVoiceIdentifier = voice.id
        previewSynthesizer.speak("Hi, I'm your AI assistant. How can I help you today?")
    }
}
