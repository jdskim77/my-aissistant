import SwiftUI
import SwiftData

struct FocusTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.taskManager) private var taskManager

    let task: TaskItem?

    @State private var session: FocusSession
    @State private var secondsRemaining: Int
    @State private var isRunning = false
    @State private var isBreak = false
    @State private var currentInterval = 1
    @State private var timer: Timer?
    @State private var showCompletionSummary = false

    // Settings
    @State private var workMinutes: Int
    @State private var breakMinutes: Int
    @State private var totalIntervals: Int

    init(task: TaskItem? = nil, workMinutes: Int = 25, breakMinutes: Int = 5, intervals: Int = 4) {
        self.task = task
        let work = workMinutes
        let brk = breakMinutes
        let session = FocusSession(
            taskID: task?.id,
            taskTitle: task?.title ?? "Focus Session",
            workDuration: work * 60,
            breakDuration: brk * 60,
            intervalsTarget: intervals
        )
        self._session = State(initialValue: session)
        self._secondsRemaining = State(initialValue: work * 60)
        self._workMinutes = State(initialValue: work)
        self._breakMinutes = State(initialValue: brk)
        self._totalIntervals = State(initialValue: intervals)
    }

    private var progress: Double {
        let total = isBreak ? session.breakDuration : session.workDuration
        guard total > 0 else { return 0 }
        return 1.0 - Double(secondsRemaining) / Double(total)
    }

    private var timeString: String {
        let m = secondsRemaining / 60
        let s = secondsRemaining % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var phaseLabel: String {
        if showCompletionSummary { return "Done!" }
        return isBreak ? "Break" : "Focus \(currentInterval)/\(totalIntervals)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showCompletionSummary {
                    completionView
                } else {
                    timerView
                }
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End") {
                        endSession()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Timer View

    private var timerView: some View {
        VStack(spacing: 32) {
            Spacer()

            // Task title
            VStack(spacing: 6) {
                if let task {
                    Text(task.icon)
                        .font(.system(size: 28))
                    Text(task.title)
                        .font(AppFonts.bodyMedium(16))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }
                Text(phaseLabel)
                    .font(AppFonts.label(14))
                    .foregroundColor(isBreak ? AppColors.accentWarm : AppColors.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background((isBreak ? AppColors.accentWarm : AppColors.accent).opacity(0.12))
                    .cornerRadius(20)
            }

            // Circular timer
            ZStack {
                // Track
                Circle()
                    .stroke(AppColors.border, lineWidth: 8)
                    .frame(width: 240, height: 240)

                // Progress
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        isBreak ? AppColors.accentWarm : AppColors.accent,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 240, height: 240)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                // Time display
                VStack(spacing: 4) {
                    Text(timeString)
                        .font(.system(size: 56, weight: .light, design: .monospaced))
                        .foregroundColor(AppColors.textPrimary)
                    Text(isBreak ? "Take a breather" : "Stay focused")
                        .font(AppFonts.caption(13))
                        .foregroundColor(AppColors.textMuted)
                }
            }

            // Interval dots
            HStack(spacing: 8) {
                ForEach(1...totalIntervals, id: \.self) { i in
                    Circle()
                        .fill(i <= session.intervalsCompleted ? AppColors.accent : (i == currentInterval ? AppColors.accent.opacity(0.4) : AppColors.border))
                        .frame(width: 10, height: 10)
                }
            }

            // Controls
            HStack(spacing: 24) {
                // Reset interval
                Button {
                    Haptics.light()
                    resetCurrentInterval()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 56, height: 56)
                        .background(AppColors.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppColors.border, lineWidth: 1))
                }

                // Play / Pause
                Button {
                    Haptics.medium()
                    toggleTimer()
                } label: {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 72, height: 72)
                        .background(isBreak ? AppColors.accentWarm : AppColors.accent)
                        .clipShape(Circle())
                }

                // Skip
                Button {
                    Haptics.light()
                    skipPhase()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 56, height: 56)
                        .background(AppColors.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppColors.border, lineWidth: 1))
                }
            }

            // Settings (only when not running)
            if !isRunning && currentInterval == 1 && !isBreak && session.intervalsCompleted == 0 {
                settingsRow
            }

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var settingsRow: some View {
        HStack(spacing: 20) {
            settingPill("Work", value: workMinutes, unit: "min") { delta in
                workMinutes = max(5, min(60, workMinutes + delta))
                session.workDuration = workMinutes * 60
                secondsRemaining = workMinutes * 60
            }
            settingPill("Break", value: breakMinutes, unit: "min") { delta in
                breakMinutes = max(1, min(30, breakMinutes + delta))
                session.breakDuration = breakMinutes * 60
            }
            settingPill("Sets", value: totalIntervals, unit: "") { delta in
                totalIntervals = max(1, min(8, totalIntervals + delta))
                session.intervalsTarget = totalIntervals
            }
        }
        .padding(.top, 8)
    }

    private func settingPill(_ label: String, value: Int, unit: String, adjust: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(AppFonts.label(11))
                .foregroundColor(AppColors.textMuted)
            HStack(spacing: 8) {
                Button { Haptics.selection(); adjust(-1) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(AppColors.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Text("\(value)\(unit.isEmpty ? "" : unit)")
                    .font(AppFonts.bodyMedium(14))
                    .foregroundColor(AppColors.textPrimary)
                    .frame(minWidth: 36)

                Button { Haptics.selection(); adjust(1) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(AppColors.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Completion View

    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundColor(AppColors.completionGreen)

            Text("Session Complete!")
                .font(AppFonts.display(28))
                .foregroundColor(AppColors.textPrimary)

            VStack(spacing: 12) {
                summaryRow("Total focus time", value: formatDuration(session.totalFocusSeconds))
                summaryRow("Intervals completed", value: "\(session.intervalsCompleted)/\(totalIntervals)")
                summaryRow("Task", value: session.taskTitle)
            }
            .padding(20)
            .background(AppColors.surface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))

            if let task, !task.done {
                Button {
                    Haptics.success()
                    taskManager?.toggleCompletion(task)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Mark Task Complete")
                    }
                    .font(AppFonts.bodyMedium(16))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.completionGreen)
                    .cornerRadius(16)
                }
            }

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(AppFonts.bodyMedium(16))
                    .foregroundColor(AppColors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.accentLight)
                    .cornerRadius(16)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Text(value)
                .font(AppFonts.bodyMedium(14))
                .foregroundColor(AppColors.textPrimary)
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m == 0 { return "\(s)s" }
        return s > 0 ? "\(m)m \(s)s" : "\(m)m"
    }

    // MARK: - Timer Logic

    private func toggleTimer() {
        if isRunning {
            pauseTimer()
        } else {
            startTimer()
        }
    }

    private func startTimer() {
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                tick()
            }
        }
    }

    private func pauseTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard secondsRemaining > 0 else { return }
        secondsRemaining -= 1

        if !isBreak {
            session.totalFocusSeconds += 1
        }

        if secondsRemaining == 0 {
            Haptics.success()
            phaseComplete()
        }
    }

    private func phaseComplete() {
        pauseTimer()

        if isBreak {
            // Break over → start next work interval
            isBreak = false
            currentInterval += 1
            secondsRemaining = session.workDuration
        } else {
            // Work interval complete
            session.intervalsCompleted += 1

            if session.intervalsCompleted >= totalIntervals {
                // All intervals done
                finishSession()
            } else {
                // Start break
                isBreak = true
                secondsRemaining = session.breakDuration
            }
        }
    }

    private func skipPhase() {
        if !isBreak {
            // Skipping a work phase still counts partial time (already tracked via tick)
            session.intervalsCompleted += 1
            if session.intervalsCompleted >= totalIntervals {
                finishSession()
                return
            }
            isBreak = true
            secondsRemaining = session.breakDuration
        } else {
            isBreak = false
            currentInterval += 1
            secondsRemaining = session.workDuration
        }
        pauseTimer()
    }

    private func resetCurrentInterval() {
        pauseTimer()
        secondsRemaining = isBreak ? session.breakDuration : session.workDuration
    }

    private func finishSession() {
        session.completed = true
        session.endedAt = Date()
        saveSession()
        withAnimation(.spring(response: 0.4)) {
            showCompletionSummary = true
        }
    }

    private func endSession() {
        pauseTimer()
        if session.intervalsCompleted > 0 || session.totalFocusSeconds > 30 {
            session.endedAt = Date()
            saveSession()
        }
    }

    private func saveSession() {
        modelContext.insert(session)
        try? modelContext.save()
    }
}
