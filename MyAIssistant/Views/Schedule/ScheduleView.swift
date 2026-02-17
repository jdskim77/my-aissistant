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

    // Add form fields
    @State private var newTitle = ""
    @State private var newIcon = "📌"
    @State private var newDate = Date()
    @State private var newCategory: TaskCategory = .personal
    @State private var newPriority: TaskPriority = .medium
    @State private var newNotes = ""

    private let iconOptions = ["📌", "✈️", "🏨", "🚐", "🧳", "🛫", "🛬", "🏜️", "💱", "📋", "📘", "🛒", "💳", "🔧", "🧘", "📞", "💊", "🎁", "📦", "🏃"]

    private var monthTitle: String {
        Date().formatted(as: "MMMM yyyy")
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

        return grouped
            .map { (date: $0.key, tasks: $0.value.sorted { $0.priority.sortOrder < $1.priority.sortOrder }) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
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

                // Timeline
                ForEach(filteredGrouped, id: \.date) { group in
                    dateSection(date: group.date, tasks: group.tasks)
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
        }
        .sheet(isPresented: $showingCalendarImport) {
            CalendarImportView()
        }
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

    // MARK: - Date section

    private func dateSection(date: Date, tasks: [TaskItem]) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let dateStr = isToday ? "Today" : date.formatted(as: "EEE, MMM d")
        let doneCount = tasks.filter(\.done).count

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(dateStr)
                    .font(AppFonts.heading(15))
                    .foregroundColor(isToday ? AppColors.accent : AppColors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(isToday ? AppColors.accentLight : Color.clear)
                    .cornerRadius(8)

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
        .padding(.top, 4)
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
                    notes: newNotes
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
    }
}
