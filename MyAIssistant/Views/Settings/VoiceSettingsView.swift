import SwiftUI
import AVFoundation

struct VoiceSettingsView: View {
    @AppStorage(AppConstants.voiceModeDefaultKey) private var voiceModeDefault = true
    @AppStorage(AppConstants.selectedVoiceIDKey) private var selectedVoiceID = ""
    @State private var previewSynthesizer = AVSpeechSynthesizer()

    private var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { qualityRank($0.quality) > qualityRank($1.quality) }
    }

    private var femaleVoices: [AVSpeechSynthesisVoice] {
        availableVoices.filter { $0.gender == .female }
    }

    private var maleVoices: [AVSpeechSynthesisVoice] {
        availableVoices.filter { $0.gender == .male }
    }

    private func qualityRank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium: return 2
        case .enhanced: return 1
        default: return 0
        }
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
                ForEach(femaleVoices, id: \.identifier) { voice in
                    voiceRow(voice)
                }
            } header: {
                Text("Female Voices")
            }

            Section {
                ForEach(maleVoices, id: \.identifier) { voice in
                    voiceRow(voice)
                }
            } header: {
                Text("Male Voices")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            previewSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func voiceRow(_ voice: AVSpeechSynthesisVoice) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.name)
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(AppColors.textPrimary)
                Text(qualityLabel(voice.quality))
                    .font(AppFonts.caption(12))
                    .foregroundColor(voice.quality == .premium ? AppColors.gold :
                                     voice.quality == .enhanced ? AppColors.accent :
                                     AppColors.textMuted)
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

            if selectedVoiceID == voice.identifier {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(AppColors.accent)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedVoiceID = voice.identifier
        }
        .padding(.vertical, 2)
    }

    private func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Default"
        }
    }

    private func previewVoice(_ voice: AVSpeechSynthesisVoice) {
        previewSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: "Hi, I'm your AI assistant. How can I help you today?")
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 1.05
        utterance.preUtteranceDelay = 0.1
        previewSynthesizer.speak(utterance)
    }
}
