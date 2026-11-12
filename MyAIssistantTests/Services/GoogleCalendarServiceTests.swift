import XCTest

/// Source-text guard for the GoogleCalendarService token-refresh coalescing
/// fix ([P1] "Google Calendar token refresh is not coalesced (actor
/// re-entrancy)").
///
/// Rationale: `GoogleCalendarService` is an `actor` that talks to the live
/// Google OAuth token endpoint over `URLSession` — there's no injectable
/// transport in this codebase to unit-test `refreshAccessToken()` against a
/// mocked concurrent-call race. `actor` isolation only serializes the
/// *synchronous* portions of a method; the `await` inside the old
/// `refreshAccessToken()` yielded the actor, so two callers hitting a 401 (or
/// racing `isTokenExpired`) at nearly the same time could both reach the
/// network call and each exchange the same refresh_token, with the second
/// exchange potentially revoking the session the first one just
/// established. This guards the exact source invariant the fix depends on:
/// every caller is routed through a single in-flight `Task` (mirroring
/// `ThrivnBackendService.refreshTokens()`), so a second concurrent caller
/// awaits the first refresh instead of starting its own.
///
/// If this fails after a legitimate refactor, verify the new code still
/// coalesces concurrent refreshes and update the guard accordingly — don't
/// just delete it.
final class GoogleCalendarServiceTests: XCTestCase {

    private func locateSourceFile() throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir
                .appendingPathComponent("MyAIssistant")
                .appendingPathComponent("Services")
                .appendingPathComponent("Calendar")
                .appendingPathComponent("GoogleCalendarService.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw XCTSkip("Could not locate GoogleCalendarService.swift by walking up from #filePath")
    }

    func testConcurrentRefreshesCoalesceIntoSingleInFlightTask() throws {
        let source = try locateSourceFile()

        XCTAssertTrue(
            source.contains("private var inFlightRefresh: Task<Void, Error>?"),
            "GoogleCalendarService should track a single in-flight refresh Task " +
            "so concurrent 401s / isTokenExpired races don't each exchange the " +
            "same refresh_token"
        )
        XCTAssertTrue(
            source.contains("if let existing = inFlightRefresh"),
            "A second concurrent caller of refreshAccessToken() must await the " +
            "existing in-flight refresh instead of starting its own"
        )
        XCTAssertTrue(
            source.contains("private func performRefreshAccessToken()"),
            "The actual network refresh must live in a separate method only " +
            "ever invoked through the inFlightRefresh coalescing wrapper"
        )

        // Both authenticatedData()'s 401-retry path and ensureValidToken()'s
        // expiry path must go through the coalescing wrapper (refreshAccessToken),
        // not call performRefreshAccessToken() directly — otherwise coalescing
        // only protects one of the two call sites.
        let directCalls = source.components(separatedBy: "performRefreshAccessToken()").count - 1
        // Expected occurrences: the `func performRefreshAccessToken()` declaration
        // itself, plus exactly one call site inside the coalescing wrapper.
        XCTAssertEqual(
            directCalls, 2,
            "performRefreshAccessToken() should only be referenced by its own " +
            "declaration and the one call site inside refreshAccessToken()'s " +
            "coalescing wrapper — any other caller would bypass coalescing"
        )
    }
}
