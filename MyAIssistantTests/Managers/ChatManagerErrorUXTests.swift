import XCTest

/// Source-text guards for the "Impeccable Screens" coach-error UX fix:
/// system errors must never be persisted/rendered as coach chat bubbles.
///
/// `ChatManager.sendMessage` isn't a pure function (it's @MainActor, hits
/// SwiftData + a live AIProvider), so these assert the source invariants the
/// behavior depends on rather than driving the full async path. If a
/// legitimate refactor moves this logic, update the guard's search strings,
/// don't delete the guard.
final class ChatManagerErrorUXTests: XCTestCase {

    private func locateSourceFile(named relativeComponents: [String]) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            var candidate = dir.appendingPathComponent("MyAIssistant")
            for component in relativeComponents {
                candidate = candidate.appendingPathComponent(component)
            }
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw XCTSkip("Could not locate \(relativeComponents.joined(separator: "/")) by walking up from #filePath")
    }

    func testCatchBlockDoesNotInsertErrorStubChatMessage() throws {
        let source = try locateSourceFile(named: ["Managers", "ChatManager.swift"])

        guard let catchRange = source.range(of: "} catch {") else {
            XCTFail("sendMessage's catch block not found — has error handling been restructured?")
            return
        }
        // Grab the catch block body up to the function's closing brace
        // (next "    func " at the same indent level, or end of file).
        let afterCatch = source[catchRange.upperBound...]
        let bodyEnd = afterCatch.range(
            of: #"\n    func "#,
            options: .regularExpression
        )?.lowerBound ?? afterCatch.endIndex
        let catchBody = String(afterCatch[afterCatch.startIndex..<bodyEnd])

        XCTAssertFalse(
            catchBody.contains("isErrorStub: true"),
            "The catch block must not construct a ChatMessage with isErrorStub: true — " +
            "system errors are shown via the inline system row (errorKind), not as a chat bubble"
        )
        XCTAssertFalse(
            catchBody.contains("modelContext.insert(") && catchBody.contains("role: .assistant"),
            "The catch block must not insert an assistant ChatMessage for a failure — " +
            "only errorKind/errorMessage should be returned to the view"
        )
        XCTAssertTrue(
            catchBody.contains("errorKind: kind"),
            "The catch block should return the categorized errorKind to the view"
        )
    }

    func testChatErrorKindHasAuthExpiredAndTransientCases() throws {
        let source = try locateSourceFile(named: ["Managers", "ChatManager.swift"])
        XCTAssertTrue(source.contains("enum ChatErrorKind"), "ChatErrorKind enum should still exist")
        XCTAssertTrue(source.contains("case authExpired"), "ChatErrorKind.authExpired should still exist")
        XCTAssertTrue(source.contains("case transient"), "ChatErrorKind.transient should still exist")
    }

    /// Codex-audit fix: a bare HTTP 401 reaching `.apiError` is a BYOK
    /// (Anthropic/OpenAI direct) invalid-key failure, never a Thrivn-backend
    /// session expiry — `ThrivnBackendService` converts a dead refresh token
    /// to `AIError.noAPIKey` before `.apiError(401)` is ever thrown for the
    /// backend path. Routing plain `.apiError(401)` to `.authExpired` would
    /// incorrectly prompt BYOK users to "Sign in" with Apple instead of
    /// telling them to fix their key.
    func testApiError401DoesNotMapToAuthExpired() throws {
        let source = try locateSourceFile(named: ["Managers", "ChatManager.swift"])

        guard let caseRange = source.range(of: "case .apiError(let code, let message):") else {
            XCTFail(".apiError case not found in sendMessage's error switch — has it been restructured?")
            return
        }
        let afterCase = source[caseRange.upperBound...]
        let branchEnd = afterCase.range(of: "} else if code == 400")?.lowerBound ?? afterCase.endIndex
        let branch401 = String(afterCase[afterCase.startIndex..<branchEnd])

        XCTAssertTrue(
            branch401.contains("if code == 401"),
            "The .apiError branch should still special-case HTTP 401"
        )
        XCTAssertFalse(
            branch401.contains("kind = .authExpired"),
            "A bare .apiError(401) (BYOK invalid key) must not be classified as " +
            ".authExpired — only ThrivnBackendService's own noAPIKey/sessionExpired " +
            "path should trigger the Apple sign-in prompt"
        )
    }
}
