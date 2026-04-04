import SwiftUI
import SwiftData

struct NLTaskParserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.taskManager) private var taskManager
    @Environment(\.keychainService) private var keychain
    @Environment(\.subscriptionTier) private var tier

    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Parsed task fields (editable before confirming)
    @State private var parsedTitle = ""
    @State private var parsedCategory: TaskCategory = .personal
    @State private var parsedPriority: TaskPriority = .medium
    @State private var parsedDate = Date()
    @State private var parsedIcon = "📌"
    @State private var parsedNotes = ""
    @State private var parsedRecurrence: TaskRecurrence = .none
    @State private var parsedDimension: LifeDimension?
    @State private var showConfirmation = false

    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showConfirmation {
                    confirmationCard
                } else {
                    inputSection
                }
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 44))
                    .foregroundColor(AppColors.accent)

                Text("Describe your task")
                    .font(AppFonts.heading(20))
                    .foregroundColor(AppColors.textPrimary)

                Text("Use natural language — I'll figure out the details")
                    .font(AppFonts.caption(14))
                    .foregroundColor(AppColors.textMuted)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                TextField("e.g. Dentist appointment next Thursday at 2pm", text: $inputText, axis: .vertical)
                    .font(AppFonts.body(16))
                    .padding(16)
                    .background(AppColors.surface)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { parseInput() }

                if let error = errorMessage {
                    Text(error)
                        .font(AppFonts.caption(13))
                        .foregroundColor(AppColors.coral)
                        .padding(.horizontal, 4)
                }

                Button {
                    parseInput()
                } label: {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isLoading ? "Parsing..." : "Parse with AI")
                    }
                    .font(AppFonts.bodyMedium(16))
                    .foregroundColor(AppColors.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading ? AppColors.textMuted : AppColors.accent)
                    .cornerRadius(16)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
            .padding(.horizontal, 20)

            // Example chips
            VStack(alignment: .leading, spacing: 8) {
                Text("Try saying:")
                    .font(AppFonts.label(12))
                    .foregroundColor(AppColors.textMuted)
                    .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        exampleChip("Grocery shopping tomorrow morning")
                        exampleChip("Team standup every Monday at 10am")
                        exampleChip("Gym at 6pm")
                        exampleChip("Pay rent on the 1st monthly")
                    }
                    .padding(.horizontal, 20)
                }
            }

            Spacer()
        }
        .onAppear { inputFocused = true }
    }

    private func exampleChip(_ text: String) -> some View {
        Button {
            inputText = text
            Haptics.light()
        } label: {
            Text(text)
                .font(AppFonts.caption(12))
                .foregroundColor(AppColors.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.accentLight)
                .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Confirmation Card

    private var confirmationCard: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Preview header
                HStack(spacing: 12) {
                    Text(parsedIcon)
                        .font(.system(size: 36))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Here's what I got")
                            .font(AppFonts.heading(18))
                            .foregroundColor(AppColors.textPrimary)
                        Text("Tap any field to adjust")
                            .font(AppFonts.caption(13))
                            .foregroundColor(AppColors.textMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Editable fields
                VStack(spacing: 1) {
                    editableField("Title") {
                        TextField("Title", text: $parsedTitle)
                            .font(AppFonts.body(15))
                    }

                    editableField("Date & Time") {
                        DatePicker("", selection: $parsedDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .tint(AppColors.accent)
                    }

                    editableField("Category") {
                        Picker("", selection: $parsedCategory) {
                            ForEach(TaskCategory.allCases) { cat in
                                Text("\(cat.icon) \(cat.rawValue)").tag(cat)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppColors.accent)
                    }

                    editableField("Priority") {
                        HStack(spacing: 8) {
                            ForEach(TaskPriority.allCases) { pri in
                                Button {
                                    Haptics.selection()
                                    parsedPriority = pri
                                } label: {
                                    Text(pri.displayName)
                                        .font(AppFonts.label(13))
                                        .foregroundColor(parsedPriority == pri ? .white : AppColors.priorityColor(pri))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(parsedPriority == pri ? AppColors.priorityColor(pri) : AppColors.priorityColor(pri).opacity(0.12))
                                        .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    editableField("Recurrence") {
                        Picker("", selection: $parsedRecurrence) {
                            ForEach(TaskRecurrence.allCases) { rec in
                                Text(rec.rawValue).tag(rec)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppColors.accent)
                    }

                    editableField("Life Dimension") {
                        DimensionPickerView(
                            selection: $parsedDimension,
                            suggestion: DimensionSuggester.suggest(title: parsedTitle, category: parsedCategory, context: nil)
                        )
                    }

                    editableField("Notes") {
                        TextField("Optional notes", text: $parsedNotes, axis: .vertical)
                            .font(AppFonts.body(15))
                            .lineLimit(1...3)
                    }
                }
                .background(AppColors.surface)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppColors.border, lineWidth: 1)
                )
                .padding(.horizontal, 20)

                // Action buttons
                VStack(spacing: 10) {
                    Button {
                        confirmTask()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Add Task")
                        }
                        .font(AppFonts.bodyMedium(16))
                        .foregroundColor(AppColors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.accent)
                        .cornerRadius(16)
                    }

                    Button {
                        showConfirmation = false
                        errorMessage = nil
                    } label: {
                        Text("Start Over")
                            .font(AppFonts.body(15))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private func editableField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppFonts.label(11))
                .foregroundColor(AppColors.textMuted)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func parseInput() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        inputFocused = false

        Task {
            do {
                let provider = try AIProviderFactory.provider(for: tier, useCase: .chat, keychain: keychain)
                let systemPrompt = AIPromptBuilder.taskParsingPrompt()
                let response = try await provider.sendMessage(
                    userMessage: text,
                    conversationHistory: [],
                    systemPrompt: systemPrompt
                )

                try parseJSON(response.content)
                Haptics.success()
                withAnimation(.spring(response: 0.35)) {
                    showConfirmation = true
                }
            } catch AIError.noAPIKey {
                errorMessage = "Add your API key in Settings to use AI parsing."
            } catch {
                errorMessage = "Couldn't parse that — try rephrasing or add manually."
            }

            isLoading = false
        }
    }

    private func parseJSON(_ raw: String) throws {
        // Strip markdown code fences if present
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleaned.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String else {
            throw AIError.parsingError
        }

        parsedTitle = title
        parsedIcon = (json["icon"] as? String) ?? "📌"
        parsedNotes = (json["notes"] as? String) ?? ""

        if let catStr = json["category"] as? String,
           let cat = TaskCategory(rawValue: catStr) {
            parsedCategory = cat
        }

        if let priStr = json["priority"] as? String,
           let pri = TaskPriority(rawValue: priStr) {
            parsedPriority = pri
        }

        if let recStr = json["recurrence"] as? String,
           let rec = TaskRecurrence(rawValue: recStr) {
            parsedRecurrence = rec
        }

        // Auto-suggest life dimension from parsed title + category
        parsedDimension = DimensionSuggester.suggest(title: parsedTitle, category: parsedCategory)

        // Parse date
        if let dateStr = json["date"] as? String {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            if let date = df.date(from: dateStr) {
                var cal = Calendar.current
                cal.timeZone = .current
                var components = cal.dateComponents([.year, .month, .day], from: date)

                // Parse time
                if let timeStr = json["time"] as? String {
                    let parts = timeStr.split(separator: ":")
                    if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
                        components.hour = h
                        components.minute = m
                    }
                }

                parsedDate = cal.date(from: components) ?? date
            }
        }
    }

    private func confirmTask() {
        let task = TaskItem(
            title: parsedTitle,
            category: parsedCategory,
            priority: parsedPriority,
            date: parsedDate,
            icon: parsedIcon,
            notes: parsedNotes,
            recurrence: parsedRecurrence
        )
        task.dimension = parsedDimension
        taskManager?.addTask(task)
        Haptics.success()
        dismiss()
    }
}
