import SwiftUI
import SwiftData

struct CheckInsView: View {
    @Environment(\.taskManager) private var taskManager
    @Environment(\.patternEngine) private var patternEngine
    @Environment(\.checkInManager) private var checkInManager
    @Query(sort: \TaskItem.date) private var allTasks: [TaskItem]
    @State private var selectedCheckIn: CheckInTime = CheckInTime.current()
    @State private var appeared = false
    @State private var showingCheckInDetail = false
    @State private var showingHistory = false

    private var todayTasks: [TaskItem] {
        allTasks.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var streak: Int {
        patternEngine?.currentStreak() ?? 0
    }

    private var completionRate: Int {
        patternEngine?.completionRate() ?? 0
    }

    private var tasksForSelected: [TaskItem] {
        taskManager?.tasksForCheckIn(selectedCheckIn) ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("Daily Check-ins")
                        .font(AppFonts.display(28))
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    Button {
                        showingHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppColors.accent)
                    }
                }
                .padding(.top, 8)

                // Horizontal check-in selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(CheckInTime.allCases) { checkIn in
                            checkInTab(checkIn)
                        }
                    }
                }

                // Selected check-in content
                VStack(spacing: 16) {
                    summaryCard
                    startCheckInButton
                    motivationCard
                    tasksSection
                }
                .offset(y: appeared ? 0 : 15)
                .opacity(appeared ? 1 : 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
        .sheet(isPresented: $showingCheckInDetail) {
            CheckInDetailView(timeSlot: selectedCheckIn)
        }
        .sheet(isPresented: $showingHistory) {
            CheckInHistoryView()
        }
    }

    // MARK: - Check-in tab

    private func checkInTab(_ checkIn: CheckInTime) -> some View {
        let isSelected = selectedCheckIn == checkIn
        let isCompleted = checkInManager?.isCheckInCompleted(checkIn) ?? false

        return Button {
            withAnimation(.spring(response: 0.3)) {
                selectedCheckIn = checkIn
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Text(checkIn.icon)
                        .font(.system(size: 24))

                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.accentWarm)
                            .offset(x: 6, y: -4)
                    }
                }
                Text(checkIn.rawValue)
                    .font(AppFonts.bodyMedium(13))
                    .foregroundColor(isSelected ? .white : AppColors.textSecondary)
                Text(checkIn.timeLabel)
                    .font(AppFonts.caption(11))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : AppColors.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? checkIn.color : AppColors.card)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.clear : AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Start check-in button

    private var startCheckInButton: some View {
        let isCompleted = checkInManager?.isCheckInCompleted(selectedCheckIn) ?? false

        return Button {
            showingCheckInDetail = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "play.circle.fill")
                    .font(.system(size: 20))
                Text(isCompleted ? "Check-in Complete" : "Start \(selectedCheckIn.rawValue) Check-in")
                    .font(AppFonts.bodyMedium(15))
            }
            .foregroundColor(isCompleted ? AppColors.accentWarm : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isCompleted ? AppColors.accentWarm.opacity(0.12) : selectedCheckIn.color)
            .cornerRadius(12)
        }
        .disabled(isCompleted)
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selectedCheckIn.icon)
                    .font(.system(size: 24))
                Text(selectedCheckIn.title)
                    .font(AppFonts.heading(18))
                    .foregroundColor(AppColors.textPrimary)
            }

            Text(selectedCheckIn.greeting)
                .font(AppFonts.body(15))
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .background(AppColors.border)

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Streak")
                        .font(AppFonts.caption(11))
                        .foregroundColor(AppColors.textMuted)
                    Text("\(streak) days")
                        .font(AppFonts.bodyMedium(14))
                        .foregroundColor(AppColors.textPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Completion")
                        .font(AppFonts.caption(11))
                        .foregroundColor(AppColors.textMuted)
                    Text("\(completionRate)%")
                        .font(AppFonts.bodyMedium(14))
                        .foregroundColor(AppColors.accentWarm)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Today")
                        .font(AppFonts.caption(11))
                        .foregroundColor(AppColors.textMuted)
                    Text("\(todayTasks.filter(\.done).count)/\(todayTasks.count)")
                        .font(AppFonts.bodyMedium(14))
                        .foregroundColor(AppColors.textPrimary)
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [selectedCheckIn.color.opacity(0.08), selectedCheckIn.color.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(selectedCheckIn.color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Motivation card

    private var motivationCard: some View {
        HStack(spacing: 12) {
            Text("💡")
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 2) {
                Text("Tip")
                    .font(AppFonts.label(11))
                    .foregroundColor(AppColors.gold)
                Text(selectedCheckIn.motivationTip)
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(AppColors.gold.opacity(0.06))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.gold.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Tasks section

    private var tasksSection: some View {
        let tasks = tasksForSelected
        let sectionTitle: String = {
            switch selectedCheckIn {
            case .morning: return "Focus Tasks"
            case .midday: return "Progress Update"
            case .afternoon: return "Day Review"
            case .night: return "Upcoming"
            }
        }()

        return VStack(alignment: .leading, spacing: 10) {
            Text(sectionTitle)
                .font(AppFonts.heading(16))
                .foregroundColor(AppColors.textPrimary)

            if tasks.isEmpty {
                Text("No tasks for this period.")
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textMuted)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(tasks, id: \.id) { task in
                    TaskCard(task: task) {
                        withAnimation(.spring(response: 0.3)) {
                            taskManager?.toggleCompletion(task)
                        }
                    }
                }
            }
        }
    }
}
