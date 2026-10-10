import XCTest
@testable import MyAIssistant

/// Source-text guard tests for the Impeccable Screens P2 polish pass.
/// Linux CI can't compile Swift (no Xcode), so these assert on literal
/// substrings in the real `.swift` source files instead of exercising
/// the SwiftUI view tree — catches a reverted fix (e.g. "Powered by
/// Claude" creeping back in) that a pure logic test can't see. Skips
/// cleanly (doesn't fail) if the source tree isn't present on the
/// runner, per the project's CI pattern.
final class ChatViewSourceGuardTests: XCTestCase {
    /// Walks up from this test file to find the repo root (identified by
    /// the presence of `MyAIssistant.xcodeproj`), then returns the path
    /// to `ChatView.swift`. Returns nil if the layout isn't found —
    /// callers should `throw XCTSkip` in that case.
    private func chatViewSourcePath() -> URL? {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("MyAIssistant.xcodeproj")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return dir
                    .appendingPathComponent("MyAIssistant/Views/Chat/ChatView.swift")
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    private func loadSource() throws -> String {
        guard let path = chatViewSourcePath(),
              let contents = try? String(contentsOf: path, encoding: .utf8) else {
            throw XCTSkip("ChatView.swift not found — source tree not available on this runner")
        }
        return contents
    }

    func test_poweredByClaudeSubtitle_isGone() throws {
        let source = try loadSource()
        XCTAssertFalse(
            source.contains("Powered by Claude"),
            "ChatView header subtitle should show a live status (Online/Thinking…), not the static 'Powered by Claude' credit. That credit still belongs in Settings/Legal, not here."
        )
        XCTAssertFalse(source.contains("Powered by OpenAI"))
    }

    func test_coachStatusLabel_hasOnlineAndThinkingStates() throws {
        let source = try loadSource()
        XCTAssertTrue(source.contains("\"Online\""))
        XCTAssertTrue(source.contains("\"Thinking…\""))
    }

    func test_micGlyph_isPresent() throws {
        let source = try loadSource()
        XCTAssertTrue(
            source.contains("mic.fill"),
            "Composer's idle action button should use a real mic SF Symbol, not just the brand orb."
        )
    }

    func test_sendArrowGlyph_isPresent() throws {
        let source = try loadSource()
        XCTAssertTrue(
            source.contains("arrow.up"),
            "Composer's action button should swap to an arrow-up send glyph once text is entered."
        )
    }

    /// Ordering guard: within the action-button ZStack, the mic state
    /// should still be reachable (not deleted entirely) alongside the
    /// send state — i.e. both glyphs coexist in the same button, not one
    /// replacing the other permanently.
    func test_micAndSendGlyphs_bothPresentInComposer() throws {
        let source = try loadSource()
        guard let micRange = source.range(of: "mic.fill"),
              let arrowRange = source.range(of: "Image(systemName: \"arrow.up\")") else {
            XCTFail("Expected both mic.fill and arrow.up glyphs in ChatView.swift")
            return
        }
        // Both should appear within the same general input-bar region —
        // use a generous character window instead of exact adjacency so
        // this doesn't become brittle to minor reordering/comments.
        let distance = abs(source.distance(from: micRange.lowerBound, to: arrowRange.lowerBound))
        XCTAssertLessThan(distance, 4000, "mic.fill and arrow.up should both live in the composer's action-button region")
    }
}
