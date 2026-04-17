import SwiftUI

/// Compact SwiftUI view for the Share Extension. Shows the shared content preview,
/// an LLM-extracted task title (editable), and Save/Cancel buttons.
struct ShareView: View {
    @State private var viewModel: ShareExtensionViewModel
    private let onSave: () -> Void
    private let onCancel: () -> Void

    init(sharedText: String?, sharedURL: URL?, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        _viewModel = State(initialValue: ShareExtensionViewModel(
            sharedText: sharedText,
            sharedURL: sharedURL
        ))
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Shared content preview
                    sharedContentPreview

                    // Task title (editable)
                    taskTitleSection

                    // Category picker
                    categoryPicker

                    // Error message
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }

            Divider()

            // Action buttons
            actionButtons
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .task {
            await viewModel.extractTask()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color(hex: "2D5016"))
            Text("Save to Thrivn")
                .font(.system(.headline, design: .rounded))
            Spacer()
            if viewModel.isExtracting {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Shared Content Preview

    private var sharedContentPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shared Content")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 6) {
                if let url = viewModel.sharedURL {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.caption)
                            .foregroundStyle(Color(hex: "2D5016"))
                        Text(url.host() ?? url.absoluteString)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let text = viewModel.sharedText, !text.isEmpty {
                    Text(text)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Task Title

    private var taskTitleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Task Title")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if viewModel.didExtractWithAI {
                    Text("AI-extracted")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color(hex: "2D5016"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: "2D5016").opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            TextField("Task title", text: $viewModel.proposedTitle)
                .font(.system(.body, design: .rounded))
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TaskCategory.allCases, id: \.rawValue) { category in
                        categoryChip(category)
                    }
                }
            }
        }
    }

    private func categoryChip(_ category: TaskCategory) -> some View {
        let isSelected = viewModel.suggestedCategory == category
        return Button {
            viewModel.suggestedCategory = category
            Haptics.selection()
        } label: {
            Text(category.rawValue)
                .font(.system(.subheadline, design: .rounded, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color(hex: "2D5016") : Color(.secondarySystemGroupedBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.light()
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.success()
                viewModel.saveTask()
                if viewModel.errorMessage == nil {
                    onSave()
                }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text("Save Task")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(Color(hex: "2D5016"))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSaving || viewModel.proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(viewModel.proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
    }
}

// Color(hex:) is provided by AppColors.swift (shared with the main app target)
