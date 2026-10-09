import XCTest

/// Source-text guard for the ThrivnBackendService refresh-token auth fix.
///
/// Rationale: `ThrivnBackendService` is an `actor` that talks to a live
/// Cloudflare Worker over `URLSession` — there's no injectable transport in
/// this codebase to unit-test `performRefresh()` against a mocked 401/403
/// response. Instead of skipping coverage entirely, this guards the exact
/// source invariant the fix depends on: that a 401/403 refresh response
/// clears `AppConstants.hasSignedInWithAppleKey` in the same branch that
/// clears the local tokens, so `AIProviderFactory` never sees an
/// inconsistent "signed in, but no refresh token" state (the diagnosed root
/// cause of spurious "Your session expired" errors).
///
/// If this fails after a legitimate refactor, verify the new code still
/// clears the signed-in flag on 401/403 and update the guard accordingly —
/// don't just delete it.
final class ThrivnBackendServiceAuthTests: XCTestCase {

    private func locateSourceFile() throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir
                .appendingPathComponent("MyAIssistant")
                .appendingPathComponent("Services")
                .appendingPathComponent("Backend")
                .appendingPathComponent("ThrivnBackendService.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw XCTSkip("Could not locate ThrivnBackendService.swift by walking up from #filePath")
    }

    func testRefreshFailureClearsSignedInFlagAlongsideTokens() throws {
        let source = try locateSourceFile()

        guard let refreshRange = source.range(of: "private func performRefresh()") else {
            XCTFail("performRefresh() not found — has it been renamed/moved?")
            return
        }

        // Narrow to the body of performRefresh (up to the next top-level
        // "private func" or "func" after it) so we're asserting about the
        // right branch, not matching clearLocalTokens() calls elsewhere
        // (e.g. signOut()/deleteAccount(), which intentionally also clear it
        // inline rather than via this shared helper).
        let afterRefresh = source[refreshRange.lowerBound...]
        let bodyEnd = afterRefresh.range(
            of: #"\n    (private |)func "#,
            options: .regularExpression,
            range: afterRefresh.index(after: afterRefresh.startIndex)..<afterRefresh.endIndex
        )?.lowerBound ?? afterRefresh.endIndex
        let body = String(afterRefresh[afterRefresh.startIndex..<bodyEnd])

        XCTAssertTrue(
            body.contains("clearLocalTokens()"),
            "performRefresh() should still clear local tokens on 401/403"
        )
        XCTAssertTrue(
            body.contains("AppConstants.hasSignedInWithAppleKey"),
            "performRefresh() must clear hasSignedInWithAppleKey on 401/403 refresh failure " +
            "so AIProviderFactory doesn't see an inconsistent signed-in state " +
            "(see 2026-10-09-coach-502-diagnosis.md)"
        )
        XCTAssertTrue(
            body.contains("removeObject(forKey: AppConstants.hasSignedInWithAppleKey)"),
            "Expected removeObject(forKey:) on hasSignedInWithAppleKey, not just a reference to the key"
        )
    }

    func testConcurrentRefreshesCoalesceIntoSingleInFlightTask() throws {
        let source = try locateSourceFile()

        XCTAssertTrue(
            source.contains("inFlightRefresh"),
            "refreshTokens() should coalesce concurrent calls via a single in-flight Task " +
            "— refresh tokens are single-use/rotating on the backend, so racing refreshes " +
            "invalidate each other's session"
        )
        XCTAssertTrue(
            source.contains("if let existing = inFlightRefresh"),
            "A second concurrent caller must await the existing in-flight refresh Task " +
            "instead of starting its own"
        )
    }
}
