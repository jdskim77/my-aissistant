#if os(watchOS)
import SwiftUI
import WatchKit

/// Tab 3: Quick 2-tap check-in from the wrist — mood + energy, done.
struct WatchQuickCheckInView: View {
    var connectivity: WatchConnectivityManager
    @State private var selectedMood: Int?
    @State private var selectedEnergy: Int?
    @State private var isSubmitted = false
    @State private var showComplete = false

    /// Boundaries MUST match iOS `CheckInTime.slot(forHour:)` (CheckIn.swift) so
    /// the same moment produces the same slot label on Watch and iPhone.
    private var currentSlot: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Morning" }
        if hour < 17 { return "Midday" }
        if hour < 21 { return "Afternoon" }
        return "Night"
    }

    private var alreadyCheckedIn: Bool {
        connectivity.scheduleData?.completedCheckIns?.contains(currentSlot) ?? false
    }

    private var allCheckInsDone: Bool {
        let completed = connectivity.scheduleData?.completedCheckIns ?? []
        return completed.count >= 4
    }

    var body: some View {
        ScrollView {
            if showComplete {
                completionView
            } else if allCheckInsDone {
                allDoneView
            } else if alreadyCheckedIn {
                alreadyDoneView
            } else {
                checkInFlow
            }
        }
        .containerBackground(for: .navigation) {
            Color(red: 0.08, green: 0.08, blue: 0.12)
        }
    }

    // MARK: - Check-In Flow

    private var checkInFlow: some View {
        VStack(spacing: 14) {
            Text("\(currentSlot) Check-In")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)

            // Mood — 3+2 layout to fit 40mm watch
            VStack(spacing: 6) {
                Text("How's your mood?")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)

                let emojis = ["", "😔", "😕", "😐", "🙂", "😄"]
                let moodLabels = ["", "Very low", "Low", "Neutral", "Good", "Great"]
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { level in
                        moodButton(level: level, emoji: emojis[level], label: moodLabels[level])
                    }
                }
                HStack(spacing: 6) {
                    ForEach(4...5, id: \.self) { level in
                        moodButton(level: level, emoji: emojis[level], label: moodLabels[level])
                    }
                }
            }

            // Energy
            if selectedMood != nil {
                VStack(spacing: 6) {
                    Text("Energy level?")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)

                    let energyLabels = ["", "Low", "Tired", "OK", "Good", "High"]
                    HStack(spacing: 6) {
                        ForEach(1...3, id: \.self) { level in
                            energyButton(level: level, label: energyLabels[level])
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(4...5, id: \.self) { level in
                            energyButton(level: level, label: energyLabels[level])
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeOut(duration: 0.2), value: selectedMood)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Button Helpers

    private func moodButton(level: Int, emoji: String, label: String) -> some View {
        Button {
            selectedMood = level
            WKInterfaceDevice.current().play(.click)
        } label: {
            Text(emoji)
                .font(.system(size: 24))
                .frame(minWidth: 44, minHeight: 44)
                .background(
                    Circle()
                        .fill(selectedMood == level ? Color.accentColor.opacity(0.3) : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mood: \(label)")
    }

    private func energyButton(level: Int, label: String) -> some View {
        Button {
            selectedEnergy = level
            WKInterfaceDevice.current().play(.click)
            submitCheckIn()
        } label: {
            Text("\(level)")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .background(
                    Circle()
                        .fill(selectedEnergy == level ? Color.green.opacity(0.3) : Color.white.opacity(0.06))
                )
                .foregroundStyle(selectedEnergy == level ? .green : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Energy: \(label)")
    }

    // MARK: - Submission

    private func submitCheckIn() {
        guard let mood = selectedMood, let energy = selectedEnergy, !isSubmitted else { return }
        isSubmitted = true

        let message: [String: Any] = [
            "quickCheckIn": true,
            "mood": mood,
            "energy": energy,
            "timeSlot": currentSlot,
            "date": Date().timeIntervalSince1970
        ]
        connectivity.sendCheckIn(message)

        WKInterfaceDevice.current().play(.success)

        withAnimation(.easeInOut(duration: 0.3)) {
            showComplete = true
        }
    }

    // MARK: - Auto-Reset (cancels on tab switch)

    private func resetAfterDelay() async {
        try? await Task.sleep(for: .seconds(4))
        guard !Task.isCancelled else { return }
        withAnimation {
            selectedMood = nil
            selectedEnergy = nil
            isSubmitted = false
            showComplete = false
        }
    }

    // MARK: - Completion View

    private var completionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)

            Text("Checked in")
                .font(.system(.headline, design: .rounded))

            if let quote = connectivity.scheduleData?.quoteText {
                Text(quote)
                    .font(.system(.caption2, design: .rounded).italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

                if let author = connectivity.scheduleData?.quoteAuthor {
                    Text("— \(author)")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .task { await resetAfterDelay() }
    }

    // MARK: - Already Done View

    private var alreadyDoneView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(.green)

            Text("\(currentSlot) check-in done")
                .font(.system(.subheadline, design: .rounded))

            if let next = connectivity.scheduleData?.nextCheckIn {
                Text("Next: \(next)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - All Done View

    private var allDoneView: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)

            Text("All check-ins complete!")
                .font(.system(.headline, design: .rounded))

            Text("You showed up for yourself today.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
#endif
