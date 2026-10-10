import XCTest

/// Source-text guard for Today redesign phase 1 (photo hero + humane
/// rows): the hero photo strip replaces the 0% ring on Home, overdue
/// tasks lose their red "Overdue" warning styling in favour of a
/// neutral "Carried over" section, and the day strip takes over from
/// the faded daypart icon row. SwiftUI view bodies aren't practical to
/// unit test without a UI test target/host app, so this guards the
/// literal strings/wiring directly in source. Skips cleanly (doesn't
/// fail) if the source tree isn't present on the runner.
final class HomeViewTodayHeroSourceGuardTests: XCTestCase {

    private func locateSourceFile(named name: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir
                .appendingPathComponent("MyAIssistant")
                .appendingPathComponent("Views")
                .appendingPathComponent("Home")
                .appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw XCTSkip("Could not locate \(name) by walking up from #filePath")
    }

    func testHomeViewUsesTodayHeroCard() throws {
        let source = try locateSourceFile(named: "HomeView.swift")
        XCTAssertTrue(
            source.contains("TodayHeroCard(") || source.contains("TodayHeroCard {"),
            "Home should render the photo-strip hero via TodayHeroCard"
        )
    }

    func testOverdueSectionIsRenamedCarriedOverAndDropsRedWarning() throws {
        let source = try locateSourceFile(named: "HomeView.swift")
        XCTAssertTrue(
            source.contains("Carried over"),
            "The overdue task section should be retitled 'Carried over' (humane rows redesign)"
        )
        XCTAssertFalse(
            source.contains("exclamationmark.triangle.fill\" : title == \"Tomorrow\""),
            "The warning-triangle icon mapping for the Overdue header should be removed once the section is retitled"
        )
    }

    func testDayStripReplacesDaypartIconRow() throws {
        let source = try locateSourceFile(named: "HomeView.swift")
        XCTAssertTrue(
            source.contains("dayStrip"),
            "A compact 4-segment day strip should replace the faded daypart icon row"
        )
    }

    func testTodayHeroCardFileExistsAndIsDecorative() throws {
        let source = try locateSourceFile(named: "TodayHeroCard.swift")
        XCTAssertTrue(
            source.contains("accessibilityHidden(true)"),
            "The hero photo is decorative and must be hidden from VoiceOver"
        )
        XCTAssertTrue(
            source.contains("Image(\"TodayHero\")"),
            "The hero should render the TodayHero imageset"
        )
    }
}
