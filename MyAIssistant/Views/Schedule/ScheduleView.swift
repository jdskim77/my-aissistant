import SwiftUI
import SwiftData

struct ScheduleView: View {
    @Environment(\.taskManager) private var taskManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.date) private var allTasks: [TaskItem]
    @State private var selectedCategory: TaskCategory? = nil
    @State private var showingAddForm = false
    @State private var showingCalendarImport = false
    @State private var appeared = false
    @State private var expandedPastDates: Set<Date> = []

    // Add form fields
    @State private var newTitle = ""
    @State private var newIcon = "📌"
    @State private var newDate = Date()
    @State private var newCategory: TaskCategory = .personal
    @State private var newPriority: TaskPriority = .medium
    @State private var newNotes = ""
    @State private var newRecurrence: TaskRecurrence = .none

    private let iconOptions = ["📌", "✈️", "🏨", "🚐", "🧳", "🛫", "🛬", "🏜️", "💱", "📋", "📘", "🛒", "💳", "🔧", "🧘", "📞", "💊", "🎁", "📦", "🏃"]

    private var monthTitle: String {
        Date().formatted(as: "MMMM yyyy")
    }

    private var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }

    private var pastGroups: [(date: Date, tasks: [TaskItem])] {
        filteredGrouped.filter { $0.date < startOfToday }
    }

    private var todayGroup: (date: Date, tasks: [TaskItem])? {
        filteredGrouped.first { Calendar.current.isDateInToday($0.date) }
    }

    private var futureGroups: [(date: Date, tasks: [TaskItem])] {
        filteredGrouped.filter { $0.date > startOfToday && !Calendar.current.isDateInToday($0.date) }
    }

    private var filteredGrouped: [(date: Date, tasks: [TaskItem])] {
        let filtered: [TaskItem]
        if let selectedCategory {
            filtered = allTasks.filter { $0.category == selectedCategory }
        } else {
            filtered = Array(allTasks)
        }

        let grouped = Dictionary(grouping: filtered) { task in
            Calendar.current.startOfDay(for: task.date)
        }

        // Dedup within each day: remove tasks with equivalent titles (handles birthday variants, etc.)
        return grouped
            .map { date, tasks in
                var seen = Set<String>()
                let unique = tasks
                    .sorted { $0.priority.sortOrder < $1.priority.sortOrder }
                    .filter { task in
                        let key = Self.deduplicationKey(for: task.title)
                        return seen.insert(key).inserted
                    }
                return (date: date, tasks: unique)
            }
            .sorted { $0.date < $1.date }
    }

    /// Normalize a task title for dedup comparison.
    /// Strips "'s Birthday", "'s birthday", "Birthday - ", lowercases, and trims whitespace
    /// so "John Smith's Birthday" and "John Smith" collapse to the same key.
    private static func deduplicationKey(for title: String) -> String {
        var key = title.lowercased()
        // Remove common birthday suffixes/prefixes
        for suffix in ["'s birthday", "'s birthday", " birthday", "'s bday"] {
            if key.hasSuffix(suffix) {
                key = String(key.dropLast(suffix.count))
            }
        }
        for prefix in ["birthday - ", "birthday: "] {
            if key.hasPrefix(prefix) {
                key = String(key.dropFirst(prefix.count))
            }
        }
        return key.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Text(monthTitle)
                        .font(AppFonts.display(28))
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    Button {
                        showingCalendarImport = true
                    } label: {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppColors.accent)
                            .padding(8)
                            .background(AppColors.accentLight)
                            .cornerRadius(8)
                    }

                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            showingAddForm.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showingAddForm ? "xmark" : "plus")
                                .font(.system(size: 14, weight: .semibold))
                            Text(showingAddForm ? "Cancel" : "Add")
                                .font(AppFonts.bodyMedium(14))
                        }
                        .foregroundColor(AppColors.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppColors.accentLight)
                        .cornerRadius(10)
                    }
                }
                .padding(.top, 8)

                // Category filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        filterPill(label: "All", category: nil)
                        ForEach(TaskCategory.allCases) { cat in
                            filterPill(label: cat.rawValue, category: cat)
                        }
                    }
                }

                // Add task form
                if showingAddForm {
                    addTaskForm
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                }

                // Past dates — collapsed & dimmed
                ForEach(pastGroups, id: \.date) { group in
                    pastDateSection(date: group.date, tasks: group.tasks)
                }

                // Today divider
                if todayGroup != nil || !futureGroups.isEmpty {
                    todayDivider
                        .id("today-scroll-anchor")
                }

                // Today — full display
                if let today = todayGroup {
                    dateSection(date: today.date, tasks: today.tasks, index: 0)
                }

                // Future — full display
                ForEach(Array(futureGroups.enumerated()), id: \.element.date) { offset, group in
                    dateSection(date: group.date, tasks: group.tasks, index: offset + 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
            // Auto-scroll to today
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation {
                    proxy.scrollTo("today-scroll-anchor", anchor: .top)
                }
            }
        }
        .sheet(isPresented: $showingCalendarImport) {
            CalendarImportView()
        }
        } // ScrollViewReader
        } // NavigationStack
    }

    // MARK: - Filter pill

    private func filterPill(label: String, category: TaskCategory?) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                selectedCategory = category
            }
        } label: {
            Text(label)
                .font(AppFonts.bodyMedium(14))
                .foregroundColor(selectedCategory == category ? .white : AppColors.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selectedCategory == category ? AppColors.accent : AppColors.card)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(selectedCategory == category ? Color.clear : AppColors.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Past date section (collapsed & dimmed)

    private func pastDateSection(date: Date, tasks: [TaskItem]) -> some View {
        let isExpanded = expandedPastDates.contains(date)
        let doneCount = tasks.filter(\.done).count
        let dateStr = date.formatted(as: "EEE, MMM d")

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    if isExpanded {
                        expandedPastDates.remove(date)
                    } else {
                        expandedPastDates.insert(date)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.textMuted)
                        .frame(width: 16)

                    Text(dateStr)
                        .font(AppFonts.heading(15))
                        .foregroundColor(AppColors.textMuted)

                    Text("— \(doneCount)/\(tasks.count) done")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textMuted)

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(tasks, id: \.id) { task in
                    NavigationLink {
                        TaskDetailView(task: task)
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            TaskCard(task: task) {
                                withAnimation(.spring(response: 0.3)) {
                                    taskManager?.toggleCompletion(task)
                                }
                            }

                            if let sourceLabel = taskManager?.calendarSourceLabel(task) {
                                HStack(spacing: 4) {
                                    Image(systemName: sourceLabel == "Google" ? "globe" : "calendar")
                                        .font(.system(size: 9, weight: .medium))
                                    Text("From \(sourceLabel)")
                                        .font(AppFonts.caption(10))
                                }
                                .foregroundColor(AppColors.textMuted)
                                .padding(.leading, 52)
                                .padding(.top, 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .opacity(0.5)
            }
        }
        .padding(.top, 4)
        .opacity(0.6)
    }

    // MARK: - Today divider

    private var todayDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(AppColors.accent)
                .frame(height: 1.5)
            Text("Today")
                .font(AppFonts.bodyMedium(13))
                .foregroundColor(AppColors.accent)
            Rectangle()
                .fill(AppColors.accent)
                .frame(height: 1.5)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Date section

    private func dateSection(date: Date, tasks: [TaskItem], index: Int) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let isTomorrow = Calendar.current.isDateInTomorrow(date)
        let dateStr = isToday ? "Today" : isTomorrow ? "Tomorrow" : date.formatted(as: "EEE, MMM d")
        let doneCount = tasks.filter(\.done).count
        let isEvenRow = index % 2 == 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if isToday {
                    Circle()
                        .fill(AppColors.accent)
                        .frame(width: 8, height: 8)
                }

                Text(dateStr)
                    .font(AppFonts.heading(15))
                    .foregroundColor(isToday ? AppColors.accent : AppColors.textPrimary)

                Text("\(doneCount)/\(tasks.count)")
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)

                Spacer()
            }

            ForEach(tasks, id: \.id) { task in
                NavigationLink {
                    TaskDetailView(task: task)
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        TaskCard(task: task) {
                            withAnimation(.spring(response: 0.3)) {
                                taskManager?.toggleCompletion(task)
                            }
                        }

                        // Calendar source indicator
                        if let sourceLabel = taskManager?.calendarSourceLabel(task) {
                            HStack(spacing: 4) {
                                Image(systemName: sourceLabel == "Google" ? "globe" : "calendar")
                                    .font(.system(size: 9, weight: .medium))
                                Text("From \(sourceLabel)")
                                    .font(AppFonts.caption(10))
                            }
                            .foregroundColor(AppColors.textMuted)
                            .padding(.leading, 52)
                            .padding(.top, 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isToday
                    ? AppColors.accentLight.opacity(0.5)
                    : isEvenRow ? AppColors.card : AppColors.surface.opacity(0.5))
        )
        .overlay(
            isToday
                ? RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.accent.opacity(0.3), lineWidth: 1.5)
                : nil
        )
    }

    // MARK: - Add task form

    private var addTaskForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Task")
                .font(AppFonts.heading(16))
                .foregroundColor(AppColors.textPrimary)

            // Icon picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Button {
                            newIcon = icon
                        } label: {
                            Text(icon)
                                .font(.system(size: 22))
                                .padding(6)
                                .background(newIcon == icon ? AppColors.accentLight : Color.clear)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TextField("Task title", text: $newTitle)
                .font(AppFonts.body(15))
                .padding(12)
                .background(AppColors.surface)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.border, lineWidth: 1)
                )

            DatePicker("Due date", selection: $newDate, displayedComponents: .date)
                .font(AppFonts.body(14))
                .tint(AppColors.accent)

            // Category selector
            HStack(spacing: 8) {
                ForEach(TaskCategory.allCases) { cat in
                    Button {
                        newCategory = cat
                    } label: {
                        Text(cat.rawValue)
                            .font(AppFonts.bodyMedium(13))
                            .foregroundColor(newCategory == cat ? .white : AppColors.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(newCategory == cat ? AppColors.accent : AppColors.surface)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(newCategory == cat ? Color.clear : AppColors.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Priority selector
            HStack(spacing: 8) {
                ForEach(TaskPriority.allCases) { pri in
                    Button {
                        newPriority = pri
                    } label: {
                        Text(pri.rawValue)
                            .font(AppFonts.bodyMedium(13))
                            .foregroundColor(newPriority == pri ? .white : AppColors.priorityColor(pri))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(newPriority == pri ? AppColors.priorityColor(pri) : AppColors.priorityColor(pri).opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Recurrence selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TaskRecurrence.allCases) { rec in
                        Button {
                            newRecurrence = rec
                        } label: {
                            HStack(spacing: 4) {
                                if rec != .none {
                                    Image(systemName: "repeat")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                Text(rec.rawValue)
                                    .font(AppFonts.bodyMedium(13))
                            }
                            .foregroundColor(newRecurrence == rec ? .white : AppColors.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(newRecurrence == rec ? AppColors.accent : AppColors.surface)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(newRecurrence == rec ? Color.clear : AppColors.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TextField("Notes (optional)", text: $newNotes)
                .font(AppFonts.body(14))
                .padding(12)
                .background(AppColors.surface)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.border, lineWidth: 1)
                )

            Button {
                guard !newTitle.isEmpty else { return }
                let task = TaskItem(
                    title: newTitle,
                    category: newCategory,
                    priority: newPriority,
                    date: newDate,
                    icon: newIcon,
                    notes: newNotes,
                    recurrence: newRecurrence
                )
                taskManager?.addTask(task)
                resetForm()
                withAnimation(.spring(response: 0.3)) {
                    showingAddForm = false
                }
            } label: {
                Text("Add Task")
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(newTitle.isEmpty ? AppColors.textMuted : AppColors.accent)
                    .cornerRadius(10)
            }
            .disabled(newTitle.isEmpty)
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
        )
    }

    private func resetForm() {
        newTitle = ""
        newIcon = "📌"
        newDate = Date()
        newCategory = .personal
        newPriority = .medium
        newNotes = ""
        newRecurrence = .none
    }
}
