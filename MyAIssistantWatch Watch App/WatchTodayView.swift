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
    }

    // MARK: - Loaded content

    @ViewBuilder
    private func content(_ data: WatchScheduleData) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                WatchBalancePulse(
                    bodyScore: data.bodyScore,
                    mindScore: data.mindScore,
                    heartScore: data.heartScore,
                    spiritScore: data.spiritScore,
                    pulseRequest: animator.pulseRequest
                )
                .padding(.bottom, 2)

                if let upNext = connectivity.upNextTask {
                    inlineNextRow(upNext)
                } else {
                    emptyTaskHint
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
        }
        .coordinateSpace(name: watchTodayCoordinateSpace)
        .onPreferenceChange(WatchDimensionPositionKey.self) { positions in
            dimensionPositions = positions
        }
        .onPreferenceChange(WatchCheckboxPositionKey.self) { pos in
            if let pos { checkboxPosition = pos }
        }
        .overlay(
            WatchParticleLayer(animator: animator)
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WatchAIPill {
                WatchVoiceChatView(connectivity: connectivity)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

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
            inlineCheckbox(for: task, color: accentColor)
                .accessibilityLabel(task.done ? "Mark \(task.title) incomplete" : "Mark \(task.title) complete")

            NavigationLink(value: task) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accentColor.opacity(0.85))
                    Text(task.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .foregroundColor(.primary)
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel(navLabel(task))
            .accessibilityHint("Opens task details")
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(
            Capsule()
                .fill(accentColor.opacity(0.10))
        )
        .overlay(
            Capsule()
                .stroke(accentColor.opacity(0.18), lineWidth: 1)
        )
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WatchAIPill {
                WatchVoiceChatView(connectivity: connectivity)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 12)
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
