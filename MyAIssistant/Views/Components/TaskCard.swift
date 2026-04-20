import SwiftUI

struct TaskCard: View {
    let task: TaskItem
    var isOverdue: Bool = false
    /// Fires on forward completion with the checkbox center in the
    /// `.homeFlight` coordinate space and the task's primary dimension. Home
    /// hands the point off to `ParticleAnimator` so a particle flies
    /// from here to the Life Balance bar. Nil in contexts without a flight
    /// destination (CheckIns, Schedule) — those rows still get the row-tint
    /// pulse, they just don't launch a particle.
    ///
    /// Declared BEFORE `onToggle` so `onToggle` stays the last parameter —
    /// existing trailing-closure call sites bind their `{ handleToggle(task) }`
    /// to it without changes.
    var onFlightLaunch: ((CGPoint, LifeDimension) -> Void)? = nil
    let onToggle: () -> Void

    @State private var isExpanded = false

    // MARK: - Completion pulse
    //
    // Brief dimension-colored row tint fired on forward completion so the tap
    // registers visually *where the user's eye already is*. The checkbox
    // fill alone is 24pt — easy to miss at speed or at larger Dynamic Type.
    // Colour matches the dimension dot + the Balance bar that bumps, so the
    // whole cause-and-effect chain reads in a single hue.
    @State private var pulseOpacity: Double = 0
    @State private var pulseTask: Task<Void, Never>?
    /// Latest checkbox center in the particle coord space (zero outside Home,
    /// which is fine — the flight callback is nil in those contexts).
    @State private var checkboxCenter: CGPoint = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pulseColor: Color {
        // BUG-02 fix: prefer the primary SCORED dimension (so pulse colour
        // matches the Balance bar that will move). Fall back to the task's
        // first dimension — this covers all-practical tasks which would
        // otherwise flash green (Body colour) and mislead the user into
        // thinking they'd just fed Body. `completionGreen` is only the
        // last-resort fallback for tasks with no dimensions at all.
        (task.dimensions.primaryScored ?? task.dimensions.first)?.color
            ?? AppColors.completionGreen
    }

    private var rowBaseColor: Color {
        isOverdue && !task.done ? AppColors.overdueBg : AppColors.card
    }

    private var checkboxColor: Color {
        task.done ? AppColors.completionGreen : AppColors.checkboxColor(task.priority)
    }

    private var timeText: String? {
        let hour = Calendar.current.component(.hour, from: task.date)
        let minute = Calendar.current.component(.minute, from: task.date)
        if hour == 0 && minute == 0 { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: task.date)
    }

    private var overdueDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: task.date)
    }

    /// VO label for the completion button. Prepends the dimension (Body /
    /// Mind / Heart / Spirit) since the visual dot that conveys it is
    /// accessibility-hidden; without this, VO users lose the category
    /// information that sighted users get from the dot.
    private var completionAccessibilityLabel: String {
        let action = task.done ? "Mark \(task.title) incomplete" : "Complete \(task.title)"
        if let dim = task.dimensions.primaryScored {
            return "\(dim.shortLabel) task. \(action)"
        }
        return action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 12) {
                // Priority-colored checkbox — 44x44 touch target
                Button {
                    // Capture intent BEFORE onToggle flips `task.done`. We
                    // only celebrate forward motion — uncompleting a task
                    // by mistake shouldn't be rewarded with a colour bloom.
                    let willComplete = !task.done
                    Haptics.success()
                    onToggle()
                    if willComplete {
                        firePulse()
                        launchFlightIfPossible()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(checkboxColor, lineWidth: 2)
                            .frame(width: 24, height: 24)

                        if task.done {
                            Circle()
                                .fill(checkboxColor)
                                .frame(width: 24, height: 24)
                            Image(systemName: "checkmark")
                                .font(AppFonts.label(12))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    // Only capture the checkbox position when a flight
                    // callback is wired (Home context). Outside Home
                    // (CheckIns / Schedule), the named coord space doesn't
                    // exist and `proxy.frame(in:)` falls back to global
                    // coords — capturing those would pollute `checkboxCenter`
                    // with values that can't be used for a particle anyway.
                    .background(
                        Group {
                            if onFlightLaunch != nil {
                                GeometryReader { proxy in
                                    let f = proxy.frame(in: .named(particleCoordinateSpace))
                                    Color.clear.preference(
                                        key: TaskCheckboxFrameKey.self,
                                        value: CGPoint(x: f.midX, y: f.midY)
                                    )
                                }
                            } else {
                                Color.clear
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(completionAccessibilityLabel)

                // Title + metadata
                VStack(alignment: .leading, spacing: 2) {
                    // `.firstTextBaseline` keeps the dot anchored to the
                    // first line of the title even when the user expands
                    // the row and the title wraps onto multiple lines.
                    // Without this, centered alignment would drift the dot
                    // to the middle of the wrapped block.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        // Dimension dot — advertises which Compass bar this
                        // task feeds, BEFORE the user taps complete. The
                        // `alignmentGuide` nudge keeps the 7pt circle
                        // optically centered on the text's x-height instead
                        // of sitting on the baseline (which would put it
                        // under the letters).
                        if let dim = task.dimensions.primaryScored {
                            Circle()
                                .fill(dim.color)
                                .frame(width: 7, height: 7)
                                .alignmentGuide(.firstTextBaseline) { d in d.height - 1 }
                                .accessibilityHidden(true)
                        }
                        Text(task.title)
                            .font(AppFonts.bodyMedium(15))
                            .foregroundColor(task.done ? AppColors.textMuted : AppColors.textPrimary)
                            .strikethrough(task.done)
                            .lineLimit(isExpanded ? nil : 1)
                    }

                    HStack(spacing: 6) {
                        if isOverdue && !task.done {
                            Text(overdueDateText)
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.overdueRed)
                        } else if let time = timeText, !task.done {
                            Text(time)
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.textMuted)
                        }
                        if task.recurrence != .none && !task.done {
                            Image(systemName: "repeat")
                                .font(AppFonts.caption(11))
                                .foregroundColor(AppColors.accent)
                        }
                    }
                }

                Spacer()

                // Priority badge (color + text, not color-only)
                if !task.done {
                    Text(task.priority.rawValue.prefix(1))
                        .font(AppFonts.label(11))
                        .foregroundColor(AppColors.checkboxColor(task.priority))
                        .frame(width: 24, height: 24)
                        .background(AppColors.checkboxColor(task.priority).opacity(0.12))
                        .cornerRadius(6)
                        .accessibilityLabel("\(task.priority.rawValue) priority")
                }

                // Expand/collapse button
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse details" : "Expand details")
            }
            .padding(.vertical, 4)

            // Expanded details
            if isExpanded {
                Divider()
                    .padding(.leading, 56)

                VStack(alignment: .leading, spacing: 10) {
                    if !task.notes.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "note.text")
                                .font(AppFonts.caption(13))
                                .foregroundColor(AppColors.textMuted)
                                .frame(width: 20)
                            Text(task.notes)
                                .font(AppFonts.body(14))
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }

                    HStack(spacing: 8) {
                        PriorityBadge(priority: task.priority)

                        Text(task.category.rawValue)
                            .font(AppFonts.label(11))
                            .foregroundColor(AppColors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColors.border.opacity(0.3))
                            .cornerRadius(6)

                        if task.recurrence != .none {
                            HStack(spacing: 3) {
                                Image(systemName: "repeat")
                                    .font(AppFonts.label(11))
                                Text(task.recurrence.rawValue)
                                    .font(AppFonts.label(11))
                            }
                            .foregroundColor(AppColors.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColors.accentLight)
                            .cornerRadius(6)
                        }

                        Spacer()

                        Text(task.date.formatted(as: "MMM d, h:mm a"))
                            .font(AppFonts.caption(12))
                            .foregroundColor(AppColors.textMuted)
                    }
                }
                .padding(.leading, 56)
                .padding(.vertical, 8)
            }
        }
        // Pulse layer rendered as an inner background so it works in BOTH
        // List contexts (Home) and plain VStack contexts (CheckInsView). The
        // listRowBackground below stays for the row base — it's a no-op
        // outside a List, but inside one it sets the full-width row tint.
        .background(pulseColor.opacity(0.16 * pulseOpacity))
        .listRowBackground(rowBaseColor)
        // BUG-05: cancel the in-flight envelope when the row scrolls offscreen
        // or the parent view tears down. Without this, a recycled row can
        // mount with stale pulseOpacity > 0.
        .onDisappear {
            pulseTask?.cancel()
            pulseOpacity = 0
        }
        .onPreferenceChange(TaskCheckboxFrameKey.self) { center in
            checkboxCenter = center
        }
    }

    /// Launches a Life Balance particle flight if the row has a scored
    /// dimension, the parent supplied a flight callback, and the checkbox
    /// center has been captured in the particle coord space. Reduce Motion
    /// is honoured at the callback level — HomeView passes nil under RM so
    /// this always delegates that decision upward.
    private func launchFlightIfPossible() {
        guard let onFlightLaunch,
              let dim = task.dimensions.primaryScored,
              checkboxCenter != .zero else { return }
        onFlightLaunch(checkboxCenter, dim)
    }

    /// Fires the row tint pulse on completion. Bloom ~150ms → hold ~250ms →
    /// fade ~600ms. Reduce Motion users still get colour feedback (the fade
    /// is not "motion" in the WCAG 2.3 sense), with timings stretched so
    /// nothing feels abrupt. Always cancels any in-flight pulse so a rapid
    /// uncomplete → re-complete reads as one fresh pulse, not a double-fire.
    private func firePulse() {
        pulseTask?.cancel()
        pulseTask = Task { @MainActor in
            let bloom: Double = reduceMotion ? 0.25 : 0.15
            let fade: Double = reduceMotion ? 0.7 : 0.6
            let holdMs: Int = 250

            withAnimation(.easeOut(duration: bloom)) { pulseOpacity = 1.0 }
            try? await Task.sleep(for: .milliseconds(Int(bloom * 1000) + holdMs))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: fade)) { pulseOpacity = 0 }
        }
    }
}

/// Per-row preference key carrying the checkbox center up to the TaskCard's
/// own `onPreferenceChange`. Scoped to the individual row — not aggregated
/// upward — so each row captures its own button position.
private struct TaskCheckboxFrameKey: PreferenceKey {
    static var defaultValue: CGPoint { .zero }
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct PriorityBadge: View {
    let priority: TaskPriority

    var body: some View {
        Text(priority.rawValue)
            .font(AppFonts.label(11))
            .foregroundColor(AppColors.priorityColor(priority))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.priorityColor(priority).opacity(0.12))
            .cornerRadius(6)
    }
}
