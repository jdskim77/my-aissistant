import XCTest

/// Source-text guard for the EveningCheckInView button-copy fix: the primary
/// action must read "Save check-in" and the old "Skip ratings" button must
/// be gone (replaced by the single "Skip tonight" link).
///
/// SwiftUI view bodies aren't practical to unit test without a UI test
/// target/host app, so this guards the literal strings the design audit
/// asked for directly in source.
final class EveningCheckInViewGuardTests: XCTestCase {

    private func locateSourceFile() throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir
                .appendingPathComponent("MyAIssistant")
                .appendingPathComponent("Views")
                .appendingPathComponent("Compass")
                .appendingPathComponent("EveningCheckInView.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw XCTSkip("Could not locate EveningCheckInView.swift by walking up from #filePath")
    }

    func testSaveCheckInButtonPresent() throws {
        let source = try locateSourceFile()
        XCTAssertTrue(
            source.contains("\"Save check-in\""),
            "Primary button copy should be 'Save check-in'"
        )
    }

    func testSkipRatingsButtonRemoved() throws {
        let source = try locateSourceFile()
        XCTAssertFalse(
            source.contains("\"Skip ratings\""),
            "'Skip ratings' button should have been removed in favor of a single 'Skip tonight' link"
        )
    }

    func testSingleSkipTonightLinkPresent() throws {
        let source = try locateSourceFile()
        XCTAssertTrue(
            source.contains("\"Skip tonight\""),
            "A single 'Skip tonight' link should preserve the skip-for-today semantics"
        )
    }
}
