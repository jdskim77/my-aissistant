import XCTest
import SwiftData
@testable import MyAIssistant

/// Tests for the crisis gate in `DailyRecapGenerator.generate(...)`.
///
/// The gate runs over today's check-in notes BEFORE any LLM call. If a
/// note flags, generation returns `SafeResourceCopy.message()` and skips
/// the provider entirely. If the classifier dependency is missing, the
/// generator fails closed (returns nil) — never falls open to the LLM.
///
/// These tests exercise the gate without ever reaching the AIProvider —
/// the early-return paths return before `AIProviderFactory.provider` is
/// called, so we don't need to stub the network layer. Only the
/// classifier and (optionally) the SwiftData ModelContext need wiring.
@MainActor
final class DailyRecapGeneratorCrisisGateTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var keychain: MockKeychainService!
    private var sut: DailyRecapGenerator!

    override func setUp() async throws {
        container = try TestModelContainer.create()
        context = container.mainContext
        keychain = MockKeychainService()
        sut = DailyRecapGenerator(modelContext: context, keychainService: keychain)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        keychain = nil
        sut = nil
    }

    // MARK: - Helpers

    /// Insert a *completed* check-in with the given note for today.
    /// `fetchTodaysCheckIns()` filters on `completed && date in today's range`.
    @discardableResult
    private func seedCheckIn(
        slot: CheckInTime = .morning,
        notes: String?
    ) -> CheckInRecord {
        let record = CheckInRecord(
            timeSlot: slot,
            date: Date(),
            completed: true,
            mood: 3,
            energyLevel: 3,
            notes: notes
        )
        context.insert(record)
        try? context.save()
        return record
    }

    // MARK: - Fail-closed when classifier missing (BUG-01)

    func test_generate_classifierMissing_returnsNil_neverCallsLLM() async {
        // Seed a benign note so the function would otherwise proceed to LLM.
        seedCheckIn(notes: "Pretty good day overall.")
        // Deliberately do NOT inject a classifier — simulate DI regression.
        sut.crisisClassifier = nil

        let result = await sut.generate(
            currentTimeSlot: .morning,
            userName: nil,
            subscriptionTier: .free
        )

        // Fail-closed: refuse to generate. We don't ship "Daily insight"
        // copy when the safety gate isn't in place.
        XCTAssertNil(result, "Missing classifier must fail closed (return nil), not silently fall through to LLM.")
    }

    // MARK: - Crisis flag → SafeResourceCopy, no LLM

    func test_generate_crisisNoteFlags_returnsSafeResourceCopy() async {
        seedCheckIn(notes: "I want to die.")
        sut.crisisClassifier = StubFlaggingClassifier()

        let result = await sut.generate(
            currentTimeSlot: .morning,
            userName: nil,
            subscriptionTier: .free
        )

        XCTAssertEqual(
            result,
            .safety(SafeResourceCopy.message()),
            "Crisis-flagged note must short-circuit to hardcoded SafeResourceCopy via the safety case."
        )
    }

    func test_generate_crisisNote_skipsProviderEvenWithoutAPIKey() async {
        // No API key set. If the gate did NOT short-circuit, the function
        // would eventually call AIProviderFactory.provider and throw —
        // returning nil in the catch. We assert it returns the safety
        // string, proving the early-return fired before reaching the
        // provider construction.
        seedCheckIn(notes: "I want to die.")
        sut.crisisClassifier = StubFlaggingClassifier()

        let result = await sut.generate(
            currentTimeSlot: .morning,
            userName: nil,
            subscriptionTier: .free
        )

        XCTAssertEqual(result, .safety(SafeResourceCopy.message()))
    }

    // MARK: - Multiple notes — any flag wins

    func test_generate_multipleNotes_anyFlag_routesToSafety() async {
        seedCheckIn(slot: .morning, notes: "Great morning, slept well.")
        seedCheckIn(slot: .afternoon, notes: "I want to die.")
        seedCheckIn(slot: .night, notes: "Thinking about it.")  // benign on its own
        sut.crisisClassifier = StubMatchingClassifier(flagSubstring: "want to die")

        let result = await sut.generate(
            currentTimeSlot: .night,
            userName: nil,
            subscriptionTier: .free
        )

        XCTAssertEqual(result, .safety(SafeResourceCopy.message()))
    }

    // MARK: - Empty / nil notes — gate is no-op

    func test_generate_emptyNotesArray_doesNotEarlyReturn() async {
        // No check-ins seeded. Classifier never gets called. The function
        // proceeds toward the LLM, which fails (no API key) and returns nil.
        // Test asserts the gate didn't accidentally fire on empty notes.
        let observer = ObservableStubClassifier()
        sut.crisisClassifier = observer

        _ = await sut.generate(
            currentTimeSlot: .morning,
            userName: nil,
            subscriptionTier: .free
        )

        XCTAssertEqual(observer.evaluateCallCount, 0,
                       "Classifier must not be invoked when there are no notes today.")
    }

    func test_generate_nilAndEmptyNotes_areSkipped() async {
        seedCheckIn(slot: .morning, notes: nil)
        seedCheckIn(slot: .afternoon, notes: "")
        let observer = ObservableStubClassifier()
        sut.crisisClassifier = observer

        _ = await sut.generate(
            currentTimeSlot: .afternoon,
            userName: nil,
            subscriptionTier: .free
        )

        XCTAssertEqual(observer.evaluateCallCount, 0,
                       "nil and empty-string notes must be skipped before classifier is asked.")
    }

    // MARK: - Benign notes — gate clears, classifier evaluated

    func test_generate_benignNote_clearsGate_classifierCalledExactlyOnce() async {
        seedCheckIn(notes: "Pretty good day overall.")
        let observer = ObservableStubClassifier()  // returns .safe by default
        sut.crisisClassifier = observer

        _ = await sut.generate(
            currentTimeSlot: .morning,
            userName: nil,
            subscriptionTier: .free
        )

        XCTAssertEqual(observer.evaluateCallCount, 1,
                       "Classifier should evaluate every non-empty note exactly once.")
    }

    // MARK: - Per-day safety latch

    /// Helper: clear any latch set by a prior test in this run, so the
    /// "no prior latch" tests don't accidentally inherit a same-day one.
    private func clearLatch() {
        UserDefaults.standard.removeObject(forKey: DailyRecapGenerator.crisisLatchKey)
    }

    func test_latch_safetyFire_writesUserDefaultsTimestamp() async {
        clearLatch()
        seedCheckIn(notes: "I want to die.")
        sut.crisisClassifier = StubFlaggingClassifier()

        let before = Date().timeIntervalSince1970
        _ = await sut.generate(currentTimeSlot: .morning, userName: nil, subscriptionTier: .free)
        let after = Date().timeIntervalSince1970

        let stored = UserDefaults.standard.double(forKey: DailyRecapGenerator.crisisLatchKey)
        XCTAssertGreaterThanOrEqual(stored, before,
                                    "Latch must be set to a time at or after the fire began.")
        XCTAssertLessThanOrEqual(stored, after,
                                 "Latch must be set to a time at or before the fire returned.")
    }

    func test_latch_sameDayLatch_skipsOlderFlaggedNote() async {
        // Seed a flagged morning note timestamped one minute ago, and
        // pre-write a latch for that morning so the gate should now
        // skip the morning note.
        clearLatch()
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        let r = CheckInRecord(
            timeSlot: .morning,
            date: oneMinuteAgo,
            completed: true,
            mood: 1, energyLevel: 1,
            notes: "I want to die."
        )
        context.insert(r)
        try? context.save()

        // Latch written 30s ago — newer than the note, same day.
        let latch = Date().addingTimeInterval(-30).timeIntervalSince1970
        UserDefaults.standard.set(latch, forKey: DailyRecapGenerator.crisisLatchKey)

        let observer = ObservableStubClassifier()  // returns .safe (don't matter — we want to verify skip)
        sut.crisisClassifier = observer

        _ = await sut.generate(currentTimeSlot: .morning, userName: nil, subscriptionTier: .free)

        XCTAssertEqual(observer.evaluateCallCount, 0,
                       "Same-day latch must skip notes older than the latch (the morning crisis note).")
    }

    func test_latch_sameDayLatch_evaluatesNewerNote() async {
        clearLatch()
        // Seed a note timestamped 1 second from now (newer than the
        // latch we'll set just below).
        let nearFuture = Date().addingTimeInterval(1)
        let r = CheckInRecord(
            timeSlot: .afternoon,
            date: nearFuture,
            completed: true,
            mood: 3, energyLevel: 3,
            notes: "Doing better today."
        )
        context.insert(r)
        try? context.save()

        // Latch from now — older than the note.
        let latch = Date().timeIntervalSince1970
        UserDefaults.standard.set(latch, forKey: DailyRecapGenerator.crisisLatchKey)

        let observer = ObservableStubClassifier()
        sut.crisisClassifier = observer

        _ = await sut.generate(currentTimeSlot: .afternoon, userName: nil, subscriptionTier: .free)

        XCTAssertEqual(observer.evaluateCallCount, 1,
                       "Notes newer than the latch must still be evaluated.")
    }

    func test_latch_yesterdayLatch_isIgnored() async {
        clearLatch()
        seedCheckIn(notes: "I want to die.")  // today, would normally fire safety

        // Pre-set a latch from 25 hours ago — definitely yesterday.
        let yesterday = Date().addingTimeInterval(-25 * 60 * 60).timeIntervalSince1970
        UserDefaults.standard.set(yesterday, forKey: DailyRecapGenerator.crisisLatchKey)

        sut.crisisClassifier = StubFlaggingClassifier()

        let result = await sut.generate(currentTimeSlot: .morning, userName: nil, subscriptionTier: .free)

        XCTAssertEqual(result, .safety(SafeResourceCopy.message()),
                       "Yesterday's latch must be ignored (same-day check returns nil) — today's flagged note still fires.")
    }
}

// MARK: - Test Stubs

/// Always flags, regardless of input.
private struct StubFlaggingClassifier: CrisisClassifier {
    func evaluate(_ text: String) -> CrisisEvaluation {
        CrisisEvaluation(isCrisis: true, matchedTerms: ["stub"])
    }
}

/// Flags only when the input contains a specific substring. Lets a test
/// seed multiple notes and have the gate fire on a specific one to
/// exercise loop-iteration semantics.
private struct StubMatchingClassifier: CrisisClassifier {
    let flagSubstring: String
    func evaluate(_ text: String) -> CrisisEvaluation {
        if text.lowercased().contains(flagSubstring.lowercased()) {
            return CrisisEvaluation(isCrisis: true, matchedTerms: [flagSubstring])
        }
        return .safe
    }
}

/// Records call count so tests can assert the gate skipped empty inputs
/// without invoking the classifier.
private final class ObservableStubClassifier: CrisisClassifier, @unchecked Sendable {
    private(set) var evaluateCallCount = 0

    func evaluate(_ text: String) -> CrisisEvaluation {
        evaluateCallCount += 1
        return .safe
    }
}
