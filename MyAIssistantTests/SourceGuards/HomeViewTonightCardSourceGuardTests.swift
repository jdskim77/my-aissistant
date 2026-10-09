import XCTest

/// Source-text guard for the Evening Flow redesign's "Tonight" card on
/// Home: a single next action ("Night check-in · 1 min") shown in the
/// evening when the night check-in isn't done yet, with the progress
/// ring demoted beneath it. SwiftUI view bodies aren't practical to
/// unit test without a UI test target/host app, so this guards the
/// literal strings/wiring directly in source. Skips cleanly (doesn't
/// fail) if the source tree isn't present on the runner.
final class HomeViewTonightCardSourceGuardTests: XCTestCase {

    private func locateSourceFile() throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir
                .appendingPathComponent("MyAIssistant")
                .appendingPathComponent("Views")
                .appendingPathComponent("Home")
                .appendingPathComponent("HomeView.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw XCTSkip("Could not locate HomeView.swift by walking up from #filePath")
    }

    func testNightCheckInOneMinuteActionPresent() throws {
        let source = try locateSourceFile()
        XCTAssertTrue(
            source.contains("Night check-in · 1 min"),
            "Tonight card's single next action should read 'Night check-in · 1 min'"
        )
    }

    func testTonightCardGatedByPureDecisionFunction() throws {
        let source = try locateSourceFile()
        XCTAssertTrue(
            source.contains("HomeProgressCalc.shouldShowTonightCard("),
            "Home should delegate the Tonight-card decision to the pure, unit-tested HomeProgressCalc.shouldShowTonightCard function"
        )
    }

    func testRemainingHabitsShownInsideTonightCard() throws {
        let source = try locateSourceFile()
        guard let cardRange = source.range(of: "private var tonightCard: some View") else {
            XCTFail("Expected a tonightCard view in HomeView.swift")
            return
        }
        let tail = source[cardRange.lowerBound...]
        XCTAssertTrue(
            tail.contains("HabitRow(habit:"),
            "Tonight card should render remaining habits inline using the existing HabitRow completion UI"
        )
    }
}
