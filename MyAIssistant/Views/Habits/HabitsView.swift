import SwiftUI
import SwiftData

struct HabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HabitItem.createdAt) private var allHabits: [HabitItem]
    @State private var showingAddHabit = false
    @State private var habitToEdit: HabitItem?

    private let calendar = Calendar.current

    private var activeHabits: [HabitItem] {
        allHabits.filter { !$0.isArchived }
    }

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    /// Last 7 days for the grid header
    private var weekDates: [Date] {
        (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if activeHabits.isEmpty {
                        emptyState
                    } else {
                        // Today's habits
                        todaySection

                        // Weekly overview grid
                        weeklyGrid

                        // Stats
                        statsSection
                    }
                }
                .padding(.bottom, 100)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.light()
                        showingAddHabit = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(AppColors.accent)
                    }
                }
            }
            .sheet(isPresented: $showingAddHabit) {
                HabitFormView(mode: .create)
            }
            .sheet(item: $habitToEdit) { habit in
                HabitFormView(mode: .edit(habit))
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Image(systemName: "leaf.fill")
                .font(.system(size: 44))
                .foregroundColor(AppColors.textMuted)
            Text("No habits yet")
                .font(AppFonts.heading(18))
                .foregroundColor(AppColors.textPrimary)
            Text("Build consistency by tracking daily habits")
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textMuted)
            Button {
                Haptics.light()
                showingAddHabit = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add First Habit")
                }
                .font(AppFonts.bodyMedium(15))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(AppColors.accent)
                .cornerRadius(14)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Today Section

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today")
                    .font(AppFonts.heading(18))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                let done = activeHabits.filter { $0.isCompletedOn(today) }.count
                Text("\(done)/\(activeHabits.count)")
                    .font(AppFonts.bodyMedium(14))
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.horizontal, 20)

            ForEach(activeHabits) { habit in
                habitRow(habit)
            }
        }
        .padding(.top, 8)
    }

    private func habitRow(_ habit: HabitItem) -> some View {
        let isDone = habit.isCompletedOn(today)
        let streak = habit.currentStreak()

        return HStack(spacing: 14) {
            // Checkbox
            Button {
                Haptics.success()
                withAnimation(.spring(response: 0.3)) {
                    habit.toggleCompletion(for: today)
                    try? modelContext.save()
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(isDone ? AppColors.completionGreen : Color(hex: habit.colorHex), lineWidth: 2.5)
                        .frame(width: 28, height: 28)
                    if isDone {
                        Circle()
                            .fill(AppColors.completionGreen)
                            .frame(width: 28, height: 28)
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(habit.icon)
                .font(.system(size: 22))

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title)
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(isDone ? AppColors.textMuted : AppColors.textPrimary)
                    .strikethrough(isDone)

                if streak > 0 {
                    Text("\(streak) day streak 🔥")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.accentWarm)
                }
            }

            Spacer()

            // Edit button
            Button {
                Haptics.light()
                habitToEdit = habit
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppColors.textMuted)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    // MARK: - Weekly Grid

    private var weeklyGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(AppFonts.heading(18))
                .foregroundColor(AppColors.textPrimary)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                // Day headers
                HStack(spacing: 0) {
                    Text("")
                        .frame(width: 100)
                    ForEach(weekDates, id: \.self) { date in
                        VStack(spacing: 2) {
                            Text(date.formatted(as: "EEE"))
                                .font(AppFonts.label(10))
                                .foregroundColor(calendar.isDateInToday(date) ? AppColors.accent : AppColors.textMuted)
                            Text(date.formatted(as: "d"))
                                .font(AppFonts.caption(12))
                                .foregroundColor(calendar.isDateInToday(date) ? AppColors.accent : AppColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 8)

                // Habit rows
                ForEach(activeHabits) { habit in
                    HStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Text(habit.icon)
                                .font(.system(size: 14))
                            Text(habit.title)
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(width: 100, alignment: .leading)

                        ForEach(weekDates, id: \.self) { date in
                            let done = habit.isCompletedOn(date)
                            let applies = habit.targetDays.appliesTo(date: date)
                            ZStack {
                                if applies {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(done ? Color(hex: habit.colorHex) : AppColors.border.opacity(0.5))
                                        .frame(width: 24, height: 24)
                                    if done {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                } else {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(AppColors.background)
                                        .frame(width: 24, height: 24)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(AppColors.surface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stats")
                .font(AppFonts.heading(18))
                .foregroundColor(AppColors.textPrimary)
                .padding(.horizontal, 20)

            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                ForEach(activeHabits) { habit in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text(habit.icon)
                                .font(.system(size: 16))
                            Text(habit.title)
                                .font(AppFonts.bodyMedium(13))
                                .foregroundColor(AppColors.textPrimary)
                                .lineLimit(1)
                        }

                        let rate = habit.completionRate(days: 30)
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: habit.colorHex))
                                .frame(width: max(4, CGFloat(rate) * 100), height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(AppColors.border)
                                .frame(height: 6)
                        }
                        .cornerRadius(3)

                        HStack {
                            Text("\(Int(rate * 100))%")
                                .font(AppFonts.label(12))
                                .foregroundColor(Color(hex: habit.colorHex))
                            Spacer()
                            Text("\(habit.currentStreak())d streak")
                                .font(AppFonts.caption(11))
                                .foregroundColor(AppColors.textMuted)
                        }
                    }
                    .padding(14)
                    .background(AppColors.surface)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
