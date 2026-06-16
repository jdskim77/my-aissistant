import XCTest
import SwiftData
@testable import MyAIssistant

/// Tests for the neutral-pulse path on `TaskManager.toggleCompletion`.
///
/// User chose to ship a "neutral whole-compass shimmer" for practical /
/// untagged task completions instead of leaving them silent. The
/// publishing rule is:
///   - Task has at least one scored dimension → publish a normal pulse
///     with that dimension and points share. (Existing behavior.)
///   - Task has no scored dimension (untagged or practical-only) →
///     publish a NEUTRAL pulse: dimension `.practical`, points 1,
///     `isNeutral: true`. The downstream consumer (BalancePulseCard)
///     branches on `isNeutral` to render a whole-card scale animation
///     instead of a colored particle on a specific bar.
///
/// These tests pin the publish-side contract. The consumer-side
/// rendering is not covered here (would need a UI test).
@MainActor
final class TaskManagerNeutralPulseTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var bus: BalancePulseBus!
    private var sut: TaskManager!

    override func setUp() async throws {
        container = try TestModelContainer.create()
        context = container.mainContext
        bus = BalancePulseBus()
        sut = TaskManager(modelContext: context)
        sut.balancePulseBus = bus
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        bus = nil
        sut = nil
    }

    // MARK: - Helpers

    private func makeAndInsertTask(
        dimensions: [LifeDimension] = [],
        category: TaskCategory = .personal
    ) -> TaskItem {
        let task = TaskItem(
            title: "Test",
            category: category,
            priority: .medium,
            date: Date(),
            done: false,
            icon: "📝"
        )
        if !dimensions.isEmpty {
            task.dimensions = dimensions
        }
        context.insert(task)
        try? context.save()
        return task
    }

    // MARK: - Scored dimension → normal pulse

    func test_completion_scoredDim_publishesScoredPulse() {
        let task = makeAndInsertTask(dimensions: [.physical])
        sut.toggleCompletion(task)

        let pulse = bus.latest
        XCTAssertNotNil(pulse, "Scored-dim completion must publish a pulse.")
        XCTAssertEqual(pulse?.dimension, .physical)
        XCTAssertEqual(pulse?.isNeutral, false,
                       "Scored-dim pulses must NOT be marked neutral.")
        // points > 0 — exact value depends on effort split logic;
        // we only pin that it's positive.
        XCTAssertGreaterThan(pulse?.points ?? 0, 0)
    }

    // MARK: - No scored dim → neutral pulse

    func test_completion_untaggedTask_publishesNeutralPulse() {
        // Untagged: dimensions array is empty — this is the
        // user-reported original-regression case (AI-created task
        // landing without a dimension tag).
        let task = makeAndInsertTask(dimensions: [])
        sut.toggleCompletion(task)

        let pulse = bus.latest
        XCTAssertNotNil(pulse, "Untagged completion must still publish a pulse (neutral).")
        XCTAssertTrue(pulse?.isNeutral ?? false,
                      "Untagged completion must be marked neutral.")
        XCTAssertEqual(pulse?.dimension, .practical,
                       "Neutral pulses use .practical as a placeholder dimension.")
        XCTAssertEqual(pulse?.points, 1,
                       "Neutral pulses carry 1 point — they don't fabricate a real score contribution.")
    }

    func test_completion_practicalOnlyTask_publishesNeutralPulse() {
        // Practical-only: dimensions = [.practical]. Has a dimension
        // but it's not scored, so primaryScored returns nil → neutral.
        let task = makeAndInsertTask(dimensions: [.practical])
        sut.toggleCompletion(task)

        let pulse = bus.latest
        XCTAssertNotNil(pulse)
        XCTAssertTrue(pulse?.isNeutral ?? false,
                      "Practical-only task must publish a neutral pulse.")
        XCTAssertEqual(pulse?.dimension, .practical)
    }

    // MARK: - Toggle back to undone — no pulse

    func test_completion_toggledBackToUndone_doesNotPublishPulse() {
        // Mark a task done so its initial completion publishes a pulse,
        // then toggle it back to undone. The second toggle should NOT
        // publish anything — un-completing a task is not a celebration.
        let task = makeAndInsertTask(dimensions: [.physical])
        sut.toggleCompletion(task)  // done = true, publishes
        let firstToken = bus.latest?.token

        sut.toggleCompletion(task)  // done = false, must NOT publish
        XCTAssertEqual(bus.latest?.token, firstToken,
                       "Toggling done→undone must not overwrite the prior pulse on the bus.")
    }

    // MARK: - Multi-dim scored task — picks primary scored

    func test_completion_multiDimScoredTask_picksPrimaryScored() {
        // Mental and Emotional both scored. primaryScored picks by
        // sortOrder (Physical < Mental < Emotional < Spiritual), so
        // Mental should win.
        let task = makeAndInsertTask(dimensions: [.emotional, .mental])
        sut.toggleCompletion(task)

        XCTAssertEqual(bus.latest?.dimension, .mental)
        XCTAssertFalse(bus.latest?.isNeutral ?? true,
                       "Multi-scored task must NOT use neutral path.")
    }

    // MARK: - Mixed scored + practical — uses scored path

    func test_completion_scoredPlusPractical_usesScoredPath() {
        // If a task is tagged both physical AND practical, the scored
        // path wins — primaryScored returns .physical and we publish a
        // normal scored pulse. Practical doesn't degrade the scored.
        let task = makeAndInsertTask(dimensions: [.physical, .practical])
        sut.toggleCompletion(task)

        XCTAssertEqual(bus.latest?.dimension, .physical)
        XCTAssertFalse(bus.latest?.isNeutral ?? true)
    }
}
