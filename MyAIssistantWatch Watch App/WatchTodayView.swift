#if os(watchOS)
import SwiftUI
import WatchKit
import WatchConnectivity

struct WatchTodayView: View {
    var connectivity: WatchConnectivityManager

    // Particle animation: lives across re-renders. Holds in-flight particles
    // and the latest pulseRequest that WatchBalancePulse watches.
    @State private var animator = WatchParticleAnimator()

    // Position tracking — populated by PreferenceKey reads. Bars publish
    // their centers from inside WatchBalancePulse; the inline next row
    // publishes its checkbox center for the particle source.
    @State private var dimensionPositions: [WatchDimension: CGPoint] = [:]
    @State private var checkboxPosition: CGPoint = .zero

    // Completion detection — diff each scheduleData update against this
    // snapshot. Tasks that were active before and are now done fire one
    // particle each, queued via the animator.
    @State private var lastDoneSnapshot: [String: Bool] = [:]
    /// Guards the first arrival from firing particles for tasks the user
    /// completed off-watch before the view ever subscribed.
    @State private var hasSeededSnapshot = false
    /// Flipped when `Try again` is tapped and the session is still
    /// unreachable. Swaps the button label to "Still offline" briefly
    /// so the tap isn't a silent no-op. Clears after 3 seconds.
    @State private var retryFailedAt: Date?

    private var retryFeedback: String {
        guard let stamp = retryFailedAt,
              Date().timeIntervalSince(stamp) < 3 else { return "Try again" }
        return "Still offline"
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let data = connectivity.scheduleData {
                content(data)
            } else if connectivity.hasAttemptedSync {
                // Sync attempted, no payload → iPhone genuinely unreachable
                // OR app not installed. Honest signal, not a 2-second guess.
                unreachableState
            } else {
                loadingState
            }
        }
        .navigationTitle("Today")
        .onAppear {
            connectivity.requestUpdate()
            // Seed snapshot so the first render doesn't fire particles for
            // tasks that were already done before the view appeared.
            if let data = connectivity.scheduleData {
                lastDoneSnapshot = Dictionary(uniqueKeysWithValues: data.tasks.map { ($0.id, $0.done) })
                hasSeededSnapshot = true
            }
        }
        .onDisappear {
            // Cancel any in-flight particle landing tasks so background
            // haptics don't fire on an unmounted view.
            animator.cancelAll()
        }
        .onChange(of: connectivity.scheduleData?.updatedAt) { _, _ in
            handleScheduleUpdate()
        }
        // When scheduleData clears (e.g. transition into unreachableState
        // after data was loaded), drop captured PreferenceKey positions so
        // a subsequent reload doesn't fire particles to stale coordinates
        // from a prior layout pass.
        .onChange(of: connectivity.scheduleData == nil) { _, isNil in
            if isNil {
                dimensionPositions.removeAll()
                checkboxPosition = .zero
                hasSeededSnapshot = false
                lastDoneSnapshot.removeAll()
            }
        }
    }

    // MARK: - Loaded content

    @ViewBuilder
    private func content(_ data: WatchScheduleData) -> some View {
        ScrollView {
            // The particle overlay must live INSIDE the ScrollView (attached
            // to the scrolling content, not the viewport) — otherwise the
            // checkbox/dimension positions reported in `watchTodayCoordinateSpace`
            // (content-space) don't match the overlay's viewport-space frame
            // once the user scrolls. Putting overlay on the inner VStack
            // keeps source/target/overlay all in the same coordinate system.
            LazyVStack(spacing: 12) {
                WatchBalancePulse(
                    bodyScore: data.bodyScore,
                    mindScore: data.mindScore,
                    heartScore: data.heartScore,
                    spiritScore: data.spiritScore,
                    pulseRequest: animator.pulseRequest
                )
                .padding(.bottom, 2)

                // Today's full task list. Renders all tasks (active +
                // completed) so tapping a row to complete shows the
                // strike-through state instead of the row vanishing —
                // and gives the user a way to un-tap a mistaken complete.
                if connectivity.todayTasks.isEmpty {
                    emptyTaskHint
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(connectivity.todayTasks) { task in
                            inlineNextRow(task)
                        }
                    }
                }

            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 4)
            .overlay(WatchParticleLayer(animator: animator))
        }
        .coordinateSpace(name: watchTodayCoordinateSpace)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            pinnedAIPill
        }
        .onPreferenceChange(WatchDimensionPositionKey.self) { positions in
            dimensionPositions = positions
        }
        .onPreferenceChange(WatchCheckboxPositionKey.self) { pos in
            if let pos { checkboxPosition = pos }
        }
    }

    // MARK: - Pinned AI pill
    //
    // Lives in `.safeAreaInset(edge: .bottom)` on the ScrollView — the
    // watchOS-native way to keep a primary action glanceable without
    // stealing vertical space from the scrollable content or breaking
    // Digital Crown scrolling. A thin Material background plus a short
    // gradient fade on top visually connects the pill to the scrolling
    // content beneath it, matching the pattern Apple uses in Mail and
    // Messages for pinned toolbars.
    private var pinnedAIPill: some View {
        // Vertical padding scales with Dynamic Type but is capped so the pill
        // can't eat more than ~30% of the screen at AX sizes on a 41mm watch.
        // The gradient is taller (16pt) atop a dark backing fill — the bare
        // ultraThinMaterial reads nearly transparent on watchOS's always-dark
        // surface, which caused a visible content seam.
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 16)
            .allowsHitTesting(false)

            WatchAIPill {
                WatchVoiceChatView(connectivity: connectivity)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, max(4, min(8, pillVerticalPadding)))
        }
        .background(Color.black.opacity(0.6))
        .background(.ultraThinMaterial)
    }

    @ScaledMetric(relativeTo: .body) private var pillVerticalPadding: CGFloat = 8

    // MARK: - Inline next row (Concept 3)
    //
    // Small dimension-tinted checkbox + arrow + title + time. Two sibling
    // tap targets: checkbox toggles completion (fires particle), the rest
    // of the row navigates to task detail. No nested Button-in-Link.

    private func inlineNextRow(_ task: WatchScheduleData.WatchTask) -> some View {
        // Tint the row with the dimension the particle will actually travel to.
        // If the task has its own dim, use that; otherwise fall back to the
        // lowest-scoring dim — the same fallback `fireCompletionAnimation`
        // uses — so the row color and the particle target stay consistent.
        let dim = primaryDimension(for: task) ?? lowestScoringDimension()
        let accentColor = dim?.color ?? Color.accentColor

        return HStack(spacing: 6) {
            // Checkbox is hidden from VoiceOver — the row-level custom
            // action below ("Mark complete/incomplete") replaces it so
            // VoiceOver users get one focusable element per task instead
            // of two adjacent buttons that double traversal cost.
            inlineCheckbox(for: task, color: accentColor)
                .accessibilityHidden(true)

            NavigationLink(value: task) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accentColor.opacity(task.done ? 0.5 : 0.85))
                    Text(task.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .foregroundColor(task.done ? .secondary : .primary)
                        .strikethrough(task.done)
                    if task.hasTime {
                        Text(task.timeString)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.leading, 2)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44) // Apple HIG min touch target for primary nav
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(
            Capsule()
                .fill(accentColor.opacity(task.done ? 0.05 : 0.10))
        )
        .overlay(
            Capsule()
                .stroke(accentColor.opacity(task.done ? 0.10 : 0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(navLabel(task))
        .accessibilityHint("Opens task details")
        .accessibilityAction(named: Text(task.done ? "Mark incomplete" : "Mark complete")) {
            handleCompletionTap(task)
        }
    }

    private func inlineCheckbox(for task: WatchScheduleData.WatchTask, color: Color) -> some View {
        Button {
            handleCompletionTap(task)
        } label: {
            ZStack {
                Circle()
                    .stroke(task.done ? color : color.opacity(0.55), lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                if task.done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(color)
                }
            }
            .frame(width: 44, height: 44) // 44pt tap target
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Position publishing lives OUTSIDE the Button label so SwiftUI's
        // press-state re-render of the label (highlight/un-highlight) doesn't
        // re-fire the PreferenceKey reduction every touch.
        .background(
            GeometryReader { geo in
                let f = geo.frame(in: .named(watchTodayCoordinateSpace))
                Color.clear.preference(
                    key: WatchCheckboxPositionKey.self,
                    value: CGPoint(x: f.midX, y: f.midY)
                )
            }
        )
    }

    // MARK: - Completion handling
    //
    // Tap-to-complete is the source of truth for the particle. We fire
    // before sending the toggle to connectivity so the visual is immediate
    // (the data layer's done-state flip arrives milliseconds later).

    private func handleCompletionTap(_ task: WatchScheduleData.WatchTask) {
        let willBeDone = !task.done
        // Forward to the data layer either way.
        connectivity.toggleTaskCompletion(task.id)
        // Animate only on incomplete → complete (spec: "does not fire on undo").
        guard willBeDone else { return }
        fireCompletionAnimation(for: task)
    }

    /// Diff handler for sync-driven completion updates (e.g. iPhone toggled
    /// the task and pushed a new schedule). Catches off-watch completions.
    ///
    /// First arrival is treated as a seed, not a transition: tasks already
    /// done before the view ever subscribed must NOT fire celebration
    /// particles, regardless of whether `onAppear` saw cached data.
    private func handleScheduleUpdate() {
        guard let tasks = connectivity.scheduleData?.tasks else { return }
        guard hasSeededSnapshot else {
            lastDoneSnapshot = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.done) })
            hasSeededSnapshot = true
            return
        }
        for task in tasks {
            let prev = lastDoneSnapshot[task.id]
            if prev == false && task.done == true {
                fireCompletionAnimation(for: task)
            }
        }
        lastDoneSnapshot = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.done) })
    }

    private func fireCompletionAnimation(for task: WatchScheduleData.WatchTask) {
        let dim = primaryDimension(for: task) ?? lowestScoringDimension() ?? .body

        // Reduce Motion or unknown source position: skip flight, in-place pulse.
        if reduceMotion || checkboxPosition == .zero || dimensionPositions[dim] == nil {
            animator.pulseInPlace(dimension: dim)
            return
        }

        animator.fire(
            dimension: dim,
            from: checkboxPosition,
            to: dimensionPositions[dim] ?? checkboxPosition
        )
    }

    private func primaryDimension(for task: WatchScheduleData.WatchTask) -> WatchDimension? {
        guard let raw = task.dimensionsRaw else { return nil }
        return raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .compactMap(WatchDimension.from(rawValue:))
            .first
    }

    /// Fallback target when the task has no dimensions tagged. Picks the
    /// dimension with the lowest KNOWN score — narratively "your action
    /// just helped where you most needed it." Nil scores are excluded
    /// from the comparison so a user with only bodyScore tracked doesn't
    /// get every untagged completion funneled to Body just because the
    /// other three ?? 5.0 fallbacks are all equal and `.body` comes first.
    /// Returns nil when no dimension has any data — caller should
    /// `pulseInPlace` on a neutral dim or skip the flight entirely.
    private func lowestScoringDimension() -> WatchDimension? {
        guard let data = connectivity.scheduleData else { return nil }
        let scored: [(WatchDimension, Double)] = [
            (.body,   data.bodyScore),
            (.mind,   data.mindScore),
            (.heart,  data.heartScore),
            (.spirit, data.spiritScore)
        ].compactMap { (dim, score) in
            score.map { (dim, $0) }
        }
        return scored.min(by: { $0.1 < $1.1 })?.0
    }

    private func navLabel(_ task: WatchScheduleData.WatchTask) -> String {
        var s = "Up next: \(task.title)"
        if task.hasTime { s += " at \(task.timeString)" }
        if task.done { s += ", completed" }
        return s
    }

    // MARK: - Empty / loading / unreachable

    private var emptyTaskHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.max")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.orange)
            Text("Nothing scheduled — tap below to add")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Syncing…")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var unreachableState: some View {
        // GeometryReader + minHeight is the canonical way to vertically
        // center inside a ScrollView — pure Spacers don't expand because
        // ScrollView gives its content unbounded height. The min-height
        // anchor pins the content to at least the viewport, so the centered
        // VStack lands in the middle until taller content forces a scroll.
        ScrollView {
            GeometryReader { geo in
                VStack(spacing: 14) {
                    Spacer(minLength: 0)
                    Image(systemName: "iphone.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Can't reach iPhone")
                        .font(.headline)
                    Text("Open the iPhone app to sync today's data")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        connectivity.requestUpdate()
                        // `requestUpdate` silently no-ops when the iPhone is
                        // unreachable — without surfacing that, the user taps
                        // and nothing visibly happens. Surface a brief "Still
                        // offline" subtitle so the tap is acknowledged.
                        if !WCSession.default.isReachable {
                            WKInterfaceDevice.current().play(.failure)
                            retryFailedAt = Date()
                            // Schedule a re-render so the label flips back
                            // to "Try again" after the 3-sec window without
                            // requiring another user interaction (the
                            // `retryFeedback` computed property reads Date()
                            // and otherwise wouldn't re-evaluate on its own).
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(3))
                                if let stamp = retryFailedAt,
                                   Date().timeIntervalSince(stamp) >= 3 {
                                    retryFailedAt = nil
                                }
                            }
                        }
                    } label: {
                        Text(retryFeedback)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .padding(.horizontal, 8)
                    Spacer(minLength: 0)
                }
                .padding()
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            pinnedAIPill
        }
    }
}

// MARK: - Source-position PreferenceKey
//
// Single optional CGPoint — the inline-row checkbox publishes its center.
// Reduce(_:_:) takes the most recent non-nil so a re-render of the same
// row doesn't keep zeroing it out.

struct WatchCheckboxPositionKey: PreferenceKey {
    static var defaultValue: CGPoint? = nil
    static func reduce(value: inout CGPoint?, nextValue: () -> CGPoint?) {
        if let n = nextValue() { value = n }
    }
}

#endif
