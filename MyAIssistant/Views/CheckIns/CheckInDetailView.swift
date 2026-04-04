import SwiftUI
import SwiftData

struct CheckInDetailView: View {
    let timeSlot: CheckInTime
    @Environment(\.dismiss) private var dismiss
    @Environment(\.taskManager) private var taskManager
    @Environment(\.patternEngine) private var patternEngine
    @Environment(\.keychainService) private var keychainService
    @Environment(\.subscriptionTier) private var tier
    @Environment(\.checkInManager) private var checkInManager
    @Environment(\.usageGateManager) private var usageGateManager
    @State private var currentStep: CheckInStep = .greeting
    @State private var isGated = false
    @State private var selectedMood: Int? = nil
    @State private var selectedEnergy: Int? = nil
    @State private var notes = ""
    @State private var aiGreeting = ""
    @State private var isLoadingGreeting = true
    @State private var record: CheckInRecord?

    private enum CheckInStep {
        case greeting
        case mood
        case energy
        case notes
        case complete
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                progressBar

                ScrollView {
                    VStack(spacing: 24) {
                        if isGated {
                            PaywallCard(
                                title: "Check-in limit reached",
                                message: "You've used all \(AppConstants.freeCheckInsPerDay) free check-ins today. Upgrade for unlimited check-ins."
                            )

                            Button {
                                dismiss()
                            } label: {
                                Text("Close")
                                    .font(AppFonts.bodyMedium(15))
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        } else {
                            switch currentStep {
                            case .greeting:
                                greetingStep
                            case .mood:
                                moodStep
                            case .energy:
                                energyStep
                            case .notes:
                                notesStep
                            case .complete:
                                completeStep
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }

                // Navigation buttons
                if currentStep != .complete {
                    navigationButtons
                }
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .onAppear {
                // Check usage gate for free tier
                if let gate = usageGateManager, !gate.canDoCheckIn(tier: tier) {
                    isGated = true
                } else {
                    loadGreeting()
                }
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        let steps: [CheckInStep] = [.greeting, .mood, .energy, .notes]
        let currentIndex = steps.firstIndex(of: currentStep) ?? 0
        let progress = currentStep == .complete ? 1.0 : Double(currentIndex) / Double(steps.count)

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 4)

                Rectangle()
                    .fill(timeSlot.color)
                    .frame(width: geo.size.width * progress, height: 4)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Greeting Step

    private var greetingStep: some View {
        VStack(spacing: 20) {
            Text(timeSlot.icon)
                .font(.system(size: 56))

            Text(timeSlot.title)
                .font(AppFonts.display(28))
                .foregroundColor(AppColors.textPrimary)

            if isLoadingGreeting {
                ProgressView()
                    .tint(timeSlot.color)
            } else {
                Text(aiGreeting)
                    .font(AppFonts.body(16))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Mood Step

    private var moodStep: some View {
        VStack(spacing: 24) {
            Text(timeSlot.icon)
                .font(.system(size: 40))

            MoodPicker(selectedMood: $selectedMood)
        }
        .padding(.top, 20)
    }

    // MARK: - Energy Step

    private var energyStep: some View {
        VStack(spacing: 20) {
            Text("Energy Level")
                .font(AppFonts.heading(16))
                .foregroundColor(AppColors.textPrimary)

            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedEnergy = level
                        }
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(
                                        selectedEnergy == level
                                            ? timeSlot.color
                                            : AppColors.surface
                                    )
                                    .frame(width: 48, height: 48)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                selectedEnergy == level
                                                    ? Color.clear
                                                    : AppColors.border,
                                                lineWidth: 1
                                            )
                                    )

                                Text("\(level)")
                                    .font(AppFonts.bodyMedium(16))
                                    .foregroundColor(
                                        selectedEnergy == level ? .white : AppColors.textPrimary
                                    )
                            }

                            Text(energyLabel(level))
                                .font(AppFonts.caption(10))
                                .foregroundColor(AppColors.textMuted)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Notes Step

    private var notesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Anything on your mind?")
                .font(AppFonts.heading(16))
                .foregroundColor(AppColors.textPrimary)

            Text("Optional — jot down a quick note about your day.")
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textSecondary)

            TextField("Today I...", text: $notes, axis: .vertical)
                .font(AppFonts.body(15))
                .lineLimit(3...6)
                .padding(14)
                .background(AppColors.surface)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        }
        .padding(.top, 20)
    }

    // MARK: - Complete Step

    private var completeStep: some View {
        VStack(spacing: 20) {
            Text("✅")
                .font(.system(size: 56))

            Text("Check-in Complete!")
                .font(AppFonts.display(24))
                .foregroundColor(AppColors.textPrimary)

            if let mood = selectedMood {
                let moods = ["", "😔", "😕", "😐", "🙂", "😄"]
                Text("Mood: \(moods[mood])  Energy: \(selectedEnergy ?? 3)/5")
                    .font(AppFonts.body(15))
                    .foregroundColor(AppColors.textSecondary)
            }

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(AppFonts.bodyMedium(16))
                    .foregroundColor(AppColors.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(timeSlot.color)
                    .cornerRadius(12)
            }
            .padding(.top, 10)
        }
        .padding(.top, 40)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if currentStep != .greeting {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        goBack()
                    }
                } label: {
                    Text("Back")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.surface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    goForward()
                }
            } label: {
                Text(currentStep == .notes ? "Complete" : "Continue")
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(AppColors.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canAdvance ? timeSlot.color : AppColors.textMuted)
                    .cornerRadius(12)
            }
            .disabled(!canAdvance)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppColors.surface)
    }

    // MARK: - Logic

    private var canAdvance: Bool {
        switch currentStep {
        case .greeting: return !isLoadingGreeting
        case .mood: return selectedMood != nil
        case .energy: return selectedEnergy != nil
        case .notes: return true
        case .complete: return true
        }
    }

    private func goForward() {
        switch currentStep {
        case .greeting:
            record = checkInManager?.startCheckIn(timeSlot: timeSlot)
            currentStep = .mood
        case .mood:
            currentStep = .energy
        case .energy:
            currentStep = .notes
        case .notes:
            finalizeCheckIn()
            currentStep = .complete
        case .complete:
            break
        }
    }

    private func goBack() {
        switch currentStep {
        case .mood: currentStep = .greeting
        case .energy: currentStep = .mood
        case .notes: currentStep = .energy
        default: break
        }
    }

    private func loadGreeting() {
        Task {
            if let manager = checkInManager {
                aiGreeting = await manager.generateGreeting(
                    timeSlot: timeSlot,
                    mood: nil,
                    keychain: keychainService,
                    tier: tier,
                    scheduleSummary: taskManager?.scheduleSummary() ?? "",
                    completionRate: patternEngine?.completionRate() ?? 0,
                    streak: patternEngine?.currentStreak() ?? 0
                )
            } else {
                aiGreeting = timeSlot.greeting
            }
            isLoadingGreeting = false
        }
    }

    private func finalizeCheckIn() {
        guard let record else { return }
        checkInManager?.completeCheckIn(
            record,
            mood: selectedMood ?? 3,
            energyLevel: selectedEnergy,
            notes: notes.isEmpty ? nil : notes,
            aiSummary: aiGreeting
        )
        usageGateManager?.recordCheckIn()
    }

    private func energyLabel(_ level: Int) -> String {
        switch level {
        case 1: return "Low"
        case 2: return "Tired"
        case 3: return "Okay"
        case 4: return "Good"
        case 5: return "High"
        default: return ""
        }
    }
}
