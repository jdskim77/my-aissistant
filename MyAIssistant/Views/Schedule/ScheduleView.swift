import SwiftUI
import SwiftData

struct ScheduleView: View {
    @Environment(\.taskManager) private var taskManager
    @Environment(\.calendarSyncManager) private var calendarSyncManager
    @Environment(\.subscriptionTier) private var tier
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.date) private var allTasks: [TaskItem]
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var showingCalendarImport = false
    @State private var showingEventScanner = false
    @State private var showScannerPaywall = false
    @State private var showingNLParser = false
    @State private var showingCheckIn = false
    @State private var checkInSlot: CheckInTime = .morning
    @State private var taskToReschedule: TaskItem?
    @State private var taskToDelete: TaskItem?
    @State private var taskToFocus: TaskItem?
    @State private var rescheduleDate = Date()

    // Quick-add
    @State private var quickAddText = ""
    @State private var quickAddExpanded = false
    @State private var newDate = Date()
    @State private var newPriority: TaskPriority = .medium
    @State private var newRecurrence: TaskRecurrence = .none

    private let calendar = Calendar.current

    // MARK: - Computed

    /// Task counts per day for DayTicker density dots
    private var taskCountsByDay: [Date: Int] {
        Dictionary(grouping: allTasks) { calendar.startOfDay(for: $0.date) }
            .mapValues(\.count)
    }

    /// Tasks for the selected day, sorted chronologically
    private var selectedDayTasks: [TaskItem] {
        let dayStart = calendar.startOfDay(for: selectedDate)
        let dayEnd = calendar.safeDate(byAdding: .day, value: 1, to: dayStart)

        // Dedup
        var seen = Set<String>()
        return allTasks
            .filter { $0.date >= dayStart && $0.date < dayEnd }
            .sorted { $0.date < $1.date }
            .filter { task in
                let key = Self.deduplicationKey(for: task.title)
                return seen.insert(key).inserted
            }
    }

    /// Check-in slots that fall on the selected day
    private var checkInSlots: [CheckInTime] {
        let isToday = calendar.isDateInToday(selectedDate)
        return isToday ? CheckInTime.allCases : []
    }

    /// Interleaved timeline: check-in prompts + tasks, sorted by time
    private var timelineItems: [TimelineItem] {
        var items: [TimelineItem] = []

        // Add tasks
        for task in selectedDayTasks {
            let hour = calendar.component(.hour, from: task.date)
            let minute = calendar.component(.minute, from: task.date)
            items.append(.task(task, sortMinutes: hour * 60 + minute))
        }

        // Add check-in slots (today only)
        for slot in checkInSlots {
            items.append(.checkIn(slot, sortMinutes: slot.hour * 60))
        }

        return items.sorted { $0.sortMinutes < $1.sortMinutes }
    }

    /// Minutes since midnight for "Up Next" calculation
    private var currentMinutes: Int {
        let now = Date()
        return calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
    }

    private var dateTitle: String {
        if calendar.isDateInToday(selectedDate) { return "Today" }
        if calendar.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        if calendar.isDateInYesterday(selectedDate) { return "Yesterday" }
        return selectedDate.formatted(as: "EEEE, MMM d")
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            // Calendar sync error — surfaced inline so the user understands
            // why their imported events aren't refreshing. Previously this
            // error was set on the manager but only displayed deep in
            // CalendarSettings, so users on Schedule saw stale data with no
            // explanation.
            if let syncError = calendarSyncManager?.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppFonts.caption(12))
                    Text("Calendar sync paused — \(syncError)")
                        .font(AppFonts.caption(12))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button {
                        Haptics.light()
                        Task { await calendarSyncManager?.syncGoogleCalendar() }
                    } label: {
                        Text("Retry")
                            .font(AppFonts.bodyMedium(12))
                    }
                    .buttonStyle(.scale)
                }
                .foregroundColor(AppColors.coral)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppColors.coral.opacity(0.08))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Calendar sync error: \(syncError). Tap retry to try again.")
            }

            // DayTicker
            DayTickerView(selectedDate: $selectedDate, taskCounts: taskCountsByDay)
                .padding(.vertical, 8)

            Divider()
                .padding(.horizontal, 16)

            // Day content
            if selectedDayTasks.isEmpty && checkInSlots.isEmpty {
                Spacer()
                emptyDayState
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(timelineItems.enumerated()), id: \.offset) { index, item in
                            timelineRow(item: item, isFirst: index == 0)
                        }
                    }
                    .padding(.bottom, 100) // space for quick-add bar
                }
            }

            // Quick-add bar (persistent at bottom)
            quickAddBar
        }
        .background(AppColors.background.ignoresSafeArea())
        .sheet(isPresented: $showingCalendarImport) {
            CalendarImportView()
        }
        .sheet(isPresented: $showingEventScanner) {
            EventScannerView()
        }
        .sheet(isPresented: $showScannerPaywall) {
            NavigationStack {
                VStack(spacing: 24) {
                    PaywallCard(
                        title: "Pro Feature",
                        message: "Event Scanner uses AI vision to turn photos of flyers, emails, and screenshots into calendar events. Upgrade to Pro to unlock."
                    ) {
                        showScannerPaywall = false
                    }
                    Button {
                        showScannerPaywall = false
                    } label: {
                        Text("Close")
                            .font(AppFonts.bodyMedium(15))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding(24)
                .navigationTitle("Upgrade")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingNLParser) {
            NLTaskParserView()
        }
        .sheet(item: $taskToFocus) { task in
            FocusTimerView(task: task)
        }
        .sheet(item: $taskToReschedule) { task in
            rescheduleSheet(for: task)
        }
        .sheet(isPresented: $showingCheckIn) {
            CheckInDetailView(timeSlot: checkInSlot)
        }
        .alert("Delete Task", isPresented: Binding(
            get: { taskToDelete != nil },
            set: { if !$0 { taskToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                guard let task = taskToDelete else { return }
                Haptics.heavy()
                withAnimation {
                    if task.externalCalendarID != nil {
                        Task { await calendarSyncManager?.deleteCalendarEvent(for: task) }
                    }
                    taskManager?.deleteTask(task)
                }
                taskToDelete = nil
            }
            Button("Cancel", role: .cancel) { taskToDelete = nil }
        } message: {
            Text("Are you sure you want to delete \"\(taskToDelete?.title ?? "")\"?")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateTitle)
                    .font(AppFonts.display(24))
                    .foregroundColor(AppColors.textPrimary)
                Text(selectedDate.formatted(as: "MMMM yyyy"))
                    .font(AppFonts.caption(13))
                    .foregroundColor(AppColors.textMuted)
            }

            Spacer()

            Button {
                Haptics.light()
                showingNLParser = true
            } label: {
                Image(systemName: "sparkles")
                    .font(AppFonts.bodyMedium(16))
                    .foregroundColor(AppColors.accent)
                    .frame(width: 44, height: 44)
                    .background(AppColors.accentLight)
                    .cornerRadius(12)
            }
            .accessibilityLabel("Add task with AI")

            Button {
                Haptics.light()
                if tier == .free {
                    showScannerPaywall = true
                } else {
                    showingEventScanner = true
                }
            } label: {
                Image(systemName: "camera.viewfinder")
                    .font(AppFonts.bodyMedium(16))
                    .foregroundColor(tier == .free ? AppColors.textMuted : AppColors.accent)
                    .frame(width: 44, height: 44)
                    .background(tier == .free ? AppColors.surface : AppColors.accentLight)
                    .cornerRadius(12)
                    .overlay {
                        if tier == .free {
                            Image(systemName: "lock.fill")
                                .font(AppFonts.caption(11))
                                .foregroundColor(AppColors.textMuted)
                                .offset(x: 14, y: -14)
                        }
                    }
            }
            .accessibilityLabel("Scan event from image")

            Button {
                Haptics.light()
                showingCalendarImport = true
            } label: {
                Image(systemName: "calendar.badge.plus")
                    .font(AppFonts.bodyMedium(16))
                    .foregroundColor(AppColors.accent)
                    .frame(width: 44, height: 44)
                    .background(AppColors.accentLight)
                    .cornerRadius(12)
            }
            .accessibilityLabel("Import from calendar")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Timeline Row

    private func timelineRow(item: TimelineItem, isFirst: Bool) -> some View {
        let isUpNext = calendar.isDateInToday(selectedDate)
            && !isFirst // don't mark first item as "up next" if it's already past
            && item.sortMinutes > currentMinutes
            && item.sortMinutes - currentMinutes < 120 // within next 2 hours

        return VStack(spacing: 0) {
            // "Up Next" marker — show before the first future item today
            if isUpNext && isFirstFutureItem(item) {
                upNextMarker
            }

            switch item {
            case .task(let task, _):
                taskTimelineRow(task)
            case .checkIn(let slot, _):
                checkInTimelineRow(slot)
            }
        }
    }

    private func isFirstFutureItem(_ item: TimelineItem) -> Bool {
        guard let firstFuture = timelineItems.first(where: { $0.sortMinutes > currentMinutes }) else {
            return false
        }
        return firstFuture.sortMinutes == item.sortMinutes
    }

    private var upNextMarker: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppColors.accent)
                .frame(width: 8, height: 8)
            Text("UP NEXT")
                .font(AppFonts.label(11))
                .foregroundColor(AppColors.accent)
            Rectangle()
                .fill(AppColors.accent)
                .frame(height: 1.5)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Task Row

    private func taskTimelineRow(_ task: TaskItem) -> some View {
        let isCalendarEvent = task.externalCalendarID != nil
        let hour = calendar.component(.hour, from: task.date)
        let minute = calendar.component(.minute, from: task.date)
        let hasTime = hour != 0 || minute != 0

        return HStack(alignment: .top, spacing: 12) {
            // Time column
            VStack {
                if hasTime {
                    Text(task.date.formatted(as: "h:mm"))
                        .font(AppFonts.mono(13))
                        .foregroundColor(AppColors.textMuted)
                    Text(task.date.formatted(as: "a"))
                        .font(AppFonts.caption(11))
                        .foregroundColor(AppColors.textMuted)
                }
            }
            .frame(width: 48, alignment: .trailing)

            // Color bar (calendar events get accent, tasks get priority color)
            RoundedRectangle(cornerRadius: 2)
                .fill(isCalendarEvent ? AppColors.skyBlue : AppColors.checkboxColor(task.priority))
                .frame(width: 4)
                .frame(minHeight: 44)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    // Checkbox (tasks and calendar events)
                    Button {
                        Haptics.success()
                        withAnimation(.spring(response: 0.3)) {
                            taskManager?.toggleCompletion(task)
                        }
                    } label: {
                        ZStack {
                            let color = isCalendarEvent
                                ? (task.done ? AppColors.completionGreen : AppColors.skyBlue)
                                : (task.done ? AppColors.completionGreen : AppColors.checkboxColor(task.priority))
                            Circle()
                                .stroke(color, lineWidth: 2)
                                .frame(width: 22, height: 22)
                            if task.done {
                                Circle()
                                    .fill(color)
                                    .frame(width: 22, height: 22)
                                Image(systemName: "checkmark")
                                    .font(AppFonts.label(11))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(AppFonts.bodyMedium(15))
                            .foregroundColor(task.done ? AppColors.textMuted : AppColors.textPrimary)
                            .strikethrough(task.done)
                            .lineLimit(2)

                        if !task.notes.isEmpty {
                            Text(task.notes)
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.textMuted)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if !task.done && !isCalendarEvent {
                        Text(task.priority.rawValue.prefix(1))
                            .font(AppFonts.label(11))
                            .foregroundColor(AppColors.checkboxColor(task.priority))
                            .frame(width: 22, height: 22)
                            .background(AppColors.checkboxColor(task.priority).opacity(0.12))
                            .cornerRadius(6)
                    }

                    if task.recurrence != .none {
                        Image(systemName: "repeat")
                            .font(AppFonts.caption(11))
                            .foregroundColor(AppColors.accent)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 20)
        .opacity(task.done ? 0.5 : 1.0)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Haptics.medium()
                taskToDelete = task
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                Haptics.light()
                taskToReschedule = task
                rescheduleDate = Date()
            } label: {
                Label("Reschedule", systemImage: "calendar.badge.clock")
            }
            .tint(AppColors.skyBlue)
            if !task.done {
                Button {
                    Haptics.light()
                    taskToFocus = task
                } label: {
                    Label("Focus", systemImage: "timer")
                }
                .tint(AppColors.accentWarm)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Haptics.success()
                withAnimation(.spring(response: 0.3)) {
                    taskManager?.toggleCompletion(task)
                }
            } label: {
                Label(task.done ? "Undo" : "Complete", systemImage: task.done ? "arrow.uturn.backward" : "checkmark.circle.fill")
            }
            .tint(AppColors.completionGreen)
        }
    }

    // MARK: - Check-in Row

    private func checkInTimelineRow(_ slot: CheckInTime) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Time column
            VStack {
                Text(String(format: "%d:00", slot.hour > 12 ? slot.hour - 12 : slot.hour))
                    .font(AppFonts.mono(13))
                    .foregroundColor(AppColors.accentWarm)
                Text(slot.hour >= 12 ? "PM" : "AM")
                    .font(AppFonts.caption(11))
                    .foregroundColor(AppColors.accentWarm)
            }
            .frame(width: 48, alignment: .trailing)

            // Color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(AppColors.accentWarm.opacity(0.5))
                .frame(width: 4, height: 44)

            // Content
            Button {
                Haptics.light()
                checkInSlot = slot
                showingCheckIn = true
            } label: {
                HStack(spacing: 8) {
                    Text(slot.icon)
                        .font(AppFonts.icon(18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(slot.rawValue) Check-in")
                            .font(AppFonts.bodyMedium(14))
                            .foregroundColor(AppColors.accentWarm)
                        Text(slot.greeting)
                            .font(AppFonts.caption(12))
                            .foregroundColor(AppColors.textMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textMuted)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppColors.accentWarm.opacity(0.08))
                )
            }
            .buttonStyle(.scale)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyDayState: some View {
        VStack(spacing: 16) {
            Image(systemName: calendar.isDateInToday(selectedDate) ? "sun.max" : "calendar")
                .font(AppFonts.icon(44))
                .foregroundColor(AppColors.textMuted)

            Text(calendar.isDateInToday(selectedDate) ? "Nothing planned for today" : "No tasks on this day")
                .font(AppFonts.heading(18))
                .foregroundColor(AppColors.textPrimary)

            Text("Type below to add a task")
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textMuted)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Quick-Add Bar

    private var quickAddBar: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 8) {
                // Expanded options
                if quickAddExpanded {
                    HStack(spacing: 12) {
                        DatePicker("", selection: $newDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .tint(AppColors.accent)

                        Spacer()

                        ForEach(TaskPriority.allCases) { pri in
                            Button {
                                Haptics.selection()
                                newPriority = pri
                            } label: {
                                Text(pri.rawValue.prefix(1))
                                    .font(AppFonts.label(12))
                                    .foregroundColor(newPriority == pri ? .white : AppColors.priorityColor(pri))
                                    .frame(width: 32, height: 32)
                                    .background(newPriority == pri ? AppColors.priorityColor(pri) : AppColors.priorityColor(pri).opacity(0.12))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                HStack(spacing: 10) {
                    Button {
                        Haptics.light()
                        withAnimation(.spring(response: 0.3)) {
                            quickAddExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: quickAddExpanded ? "chevron.down" : "slider.horizontal.3")
                            .font(AppFonts.bodyMedium(14))
                            .foregroundColor(AppColors.accent)
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel(quickAddExpanded ? "Collapse options" : "Show options")

                    TextField("What needs to get done?", text: $quickAddText)
                        .font(AppFonts.body(15))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppColors.surface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                        .submitLabel(.done)
                        .onSubmit { submitQuickAdd() }

                    Button {
                        submitQuickAdd()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(AppFonts.icon(32))
                            .foregroundColor(quickAddText.trimmingCharacters(in: .whitespaces).isEmpty ? AppColors.textMuted : AppColors.accent)
                    }
                    .disabled(quickAddText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Add task")
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 10)
            .background(AppColors.surface.ignoresSafeArea(edges: .bottom))
        }
    }

    private func submitQuickAdd() {
        let title = quickAddText.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        Haptics.success()
        let taskDate = quickAddExpanded ? newDate : selectedDate
        let task = TaskItem(
            title: title,
            category: .personal,
            priority: newPriority,
            date: taskDate,
            icon: "📌",
            recurrence: newRecurrence
        )
        taskManager?.addTask(task)
        quickAddText = ""
        newPriority = .medium
        newRecurrence = .none
        if quickAddExpanded {
            withAnimation(.spring(response: 0.3)) {
                quickAddExpanded = false
            }
        }
    }

    // MARK: - Reschedule Sheet

    private func rescheduleSheet(for task: TaskItem) -> some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Reschedule \"\(task.title)\"")
                    .font(AppFonts.heading(17))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                HStack(spacing: 12) {
                    quickRescheduleButton("Tomorrow", daysFromNow: 1, task: task)
                    quickRescheduleButton("In 3 days", daysFromNow: 3, task: task)
                    quickRescheduleButton("Next week", daysFromNow: 7, task: task)
                }

                Divider()

                DatePicker("Pick a date", selection: $rescheduleDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .tint(AppColors.accent)

                Button {
                    Haptics.success()
                    taskManager?.rescheduleTask(task, to: rescheduleDate)
                    taskToReschedule = nil
                } label: {
                    Text("Reschedule")
                        .font(AppFonts.bodyMedium(16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.accent)
                        .cornerRadius(16)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { taskToReschedule = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func quickRescheduleButton(_ label: String, daysFromNow: Int, task: TaskItem) -> some View {
        Button {
            Haptics.light()
            let target = Calendar.current.safeDate(byAdding: .day, value: daysFromNow, to: Date())
            taskManager?.rescheduleTask(task, to: target)
            taskToReschedule = nil
        } label: {
            Text(label)
                .font(AppFonts.label(13))
                .foregroundColor(AppColors.accent)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(AppColors.accentLight)
                .cornerRadius(12)
        }
        .buttonStyle(.scale)
    }

    // MARK: - Helpers

    private static func deduplicationKey(for title: String) -> String {
        var key = title.lowercased()
        for suffix in ["'s birthday", "\u{2019}s birthday", " birthday", "'s bday"] {
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
}

// MARK: - Timeline Item

private enum TimelineItem {
    case task(TaskItem, sortMinutes: Int)
    case checkIn(CheckInTime, sortMinutes: Int)

    var sortMinutes: Int {
        switch self {
        case .task(_, let m): return m
        case .checkIn(_, let m): return m
        }
    }
}
