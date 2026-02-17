import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.taskManager) private var taskManager
    @Environment(\.patternEngine) private var patternEngine
    @Query(sort: \TaskItem.date) private var allTasks: [TaskItem]
    @State private var appeared = false
    @State private var showingCheckIn = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private var formattedDate: String {
        Date().formatted(as: "EEEE, MMMM d")
    }

    private var todayTasks: [TaskItem] {
        allTasks.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var completedTodayCount: Int {
        todayTasks.filter(\.done).count
    }

    private var highPriorityUpcoming: [TaskItem] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return Array(
            allTasks
                .filter { $0.date >= startOfDay && !$0.done && $0.priority == .high }
                .prefix(3)
        )
    }

    private var streak: Int {
        patternEngine?.currentStreak() ?? 0
    }

    private var checkinHistory: [Bool] {
        patternEngine?.checkInConsistency() ?? Array(repeating: false, count: 7)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Greeting header
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting)
                        .font(AppFonts.display(32))
                        .foregroundColor(AppColors.textPrimary)
                    Text(formattedDate)
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(.top, 8)
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)

                // Next check-in card (tappable)
                Button {
                    showingCheckIn = true
                } label: {
                    nextCheckInCard
                }
                .buttonStyle(.plain)
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)

                // Stats row
                HStack(spacing: 12) {
                    StatCard(
                        title: "Today's Tasks",
                        value: "\(todayTasks.count)",
                        icon: "📋",
                        color: AppColors.accent
                    )
                    StatCard(
                        title: "Completed",
                        value: "\(completedTodayCount)",
                        icon: "✅",
                        color: AppColors.accentWarm
                    )
                    StatCard(
                        title: "Streak",
                        value: "\(streak)",
                        icon: "🔥",
                        color: AppColors.coral
                    )
                }
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)

                // Streak card
                streakCard
                    .offset(y: appeared ? 0 : 20)
                    .opacity(appeared ? 1 : 0)

                // High priority upcoming
                if !highPriorityUpcoming.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("High Priority")
                            .font(AppFonts.heading(18))
                            .foregroundColor(AppColors.textPrimary)

                        ForEach(highPriorityUpcoming, id: \.id) { task in
                            TaskCard(task: task) {
                                withAnimation(.spring(response: 0.3)) {
                                    taskManager?.toggleCompletion(task)
                                }
                            }
                        }
                    }
                    .offset(y: appeared ? 0 : 20)
                    .opacity(appeared ? 1 : 0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
        }
        .sheet(isPresented: $showingCheckIn) {
            CheckInDetailView(timeSlot: CheckInTime.next())
        }
    }

    // MARK: - Next check-in card

    private var nextCheckInCard: some View {
        let next = CheckInTime.next()
        return HStack(spacing: 14) {
            Text(next.icon)
                .font(.system(size: 28))

            VStack(alignment: .leading, spacing: 3) {
                Text("Next: \(next.title)")
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(AppColors.textPrimary)
                Text(next.timeLabel)
                    .font(AppFonts.caption(13))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppColors.textMuted)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [next.color.opacity(0.08), next.color.opacity(0.03)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(next.color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Streak card

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🔥")
                    .font(.system(size: 20))
                Text("\(streak)-day streak")
                    .font(AppFonts.heading(17))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
            }

            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    let active = checkinHistory[i]
                    Circle()
                        .fill(active ? AppColors.accentWarm : AppColors.border)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: active ? "checkmark" : "")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
            }

            let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    Text(days[i])
                        .font(AppFonts.caption(10))
                        .foregroundColor(AppColors.textMuted)
                        .frame(width: 28)
                }
            }
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
        )
    }
}
