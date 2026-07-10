# Audit — Test coverage gaps
**Run:** /overnight 2026-05-04
**Method:** count source/test files, identify managers/services without tests, rank by file size as a proxy for surface area.

## Headline numbers

| Metric | Count | Read |
|---|--:|---|
| Manager source files | 26 | total managers |
| Manager test files | 11 | 42% have at least one test file |
| Service source files | 27 | total services |
| Service test files | 10 | 37% have at least one test file |
| Test files on disk | 41 | actual `.swift` test files |
| Tests registered in `.pbxproj` | 6 | **only 6 are wired into the target** |

## Critical observation

**35 of 41 test files on disk are NOT registered in the Xcode test target.** That includes everything written this session (auto-advance gates, crisis classifier, recap gate, parser, neutral pulse, history filter) AND a large set of pre-existing model/service/manager tests that someone added at some point.

This means: **right now, only ~15% of the test code in the repository runs.**

The user must drag the unregistered files into the test target before any of this work pays off. Once registered:

- Pre-existing untested files: `ActivityEntryTests`, `AlarmEntryTests`, `CalendarLinkTests`, `CheckInRecordTests`, `ChatMessageTests`, `DailySnapshotTests`, `FocusSessionTests`, `HabitItemTests`, `KeychainServiceTests`, `SpeechRecognizerTests`, `SpeechSynthesizerTests`, `SubscriptionTierTests`, `TaskCategoryTests`, `TaskItemTests`, `TaskPriorityTests`, `UsageTrackerTests`, `UserProfileTests`, `VariedGreetingBuilderTests`, `WatchScheduleDataTests`, `AIProviderFactoryTests`, `AIProviderTests`, `AIPromptBuilderTests`.

- Newly-written this session: `KeywordCrisisClassifierTests`, `DailyRecapGeneratorCrisisGateTests`, `ChatMessageHistoryFilterTests`, `ChatManagerParserTests`, `TaskManagerNeutralPulseTests`.

That's a coverage step-change worth a single 10-min Xcode session.

## Untested managers — ranked by surface area

| Lines | Manager | Note |
|--:|---|---|
| 1183 | **BalanceManager** | God-class; flagged by prior audit for split. Tests should accompany the split — write a black-box behavior contract first. |
| 809 | **NudgeEngine** | Phase 1 scaffolding with kill switch on. Logic is gated; tests would lock in the rule loop, frequency caps, dedup, quiet hours. |
| 805 | **ChatManager** | The `parseResponseTags` + `shouldSendToAI` paths are now tested. Missing: `send()` happy path, action-tag execution, error-stub generation, network-failure branch. |
| 475 | ParticleAnimator | Queue ordering, suppression window, haptic dedup. Concurrent-Task heavy — Task-isolation tests. |
| 464 | CheckInBehaviorEngine | Adaptive-window math, learning rate, completion stats. Math-heavy — pure unit tests work well here. |
| 329 | WatchSyncManager | WCSession bridge — needs a stubbable WCSession to test reachability transitions, schedule-payload encoding. |
| 324 | InsightEngine | Pattern-detection thresholds. |
| 214 | HabitReminderCoordinator | Reminder scheduling order. |
| 213 | DimensionSuggester | Heuristic mapping; pure function tests work well. |
| 181 | NudgeTypes | Enum tests + sortOrder. |
| 168 | HabitManager | Just gained `else` branch for neutral pulse — needs a test pinning that contract (parallel to `TaskManagerNeutralPulseTests`). |
| 161 | PostLowMoodCheckInRule | Predicate logic; pure function tests. |
| 153 | WeatherManager | Network + cache; partially testable. |
| 125 | NudgeComposer | Pure function — easy to test. |
| 117 | WindowedHabitRule | Predicate logic. |
| 98 | WeakDimensionWithOpenWindowRule | Predicate logic. |

## Recommended fix order

### Day 1 (~2h, no new code) — registration only

1. Drag all 35 unregistered test files into the Xcode test target.
2. Run Cmd+U. Expect failures from any test files written against an older codebase shape.
3. Triage failures. Fix or skip with a `// TODO` comment.

### Week 1 — close the highest-value gaps

4. **HabitManagerNeutralPulseTests** (~30 min) — mirrors `TaskManagerNeutralPulseTests`, pins the new neutral-pulse contract.
5. **NudgeComposer** + **DimensionSuggester** + **NudgeTypes** + **WindowedHabitRule** + **WeakDimensionWithOpenWindowRule** + **PostLowMoodCheckInRule** (~2h total) — all pure functions, very high test ROI.
6. **CheckInBehaviorEngine** math (~1h) — adaptive window calculation under different completion patterns.

### Week 2 — wider coverage

7. **NudgeEngine** rule loop with mocked deps (~3h).
8. **InsightEngine** thresholds (~2h).
9. **ChatManager.send()** happy path with stubbed provider (~2h).
10. **ParticleAnimator** queue + dedup (~3h).

### Multi-week

11. **BalanceManager** — write tests AS PART OF the god-class split refactor. ~2 days.
12. **WatchSyncManager** — needs WCSession protocol abstraction to be testable. ~1 day.
13. **WeatherManager** — needs URLProtocol mock. ~half day.

## Other notes

### Existing test files reference outdated APIs?

Before registering, eyeball each unregistered test file. Some may have been written months ago and reference APIs that have since changed (e.g. tuples reordered, function signatures evolved, `Tab` → `AppTab`). Failing tests on first run are expected — fix them or skip with a comment.

### Test infrastructure

- `TestModelContainer` exists at `MyAIssistantTests/Utilities/`.
- `MockKeychainService` exists.
- `MockAIProvider` exists.
- No mock for `BalancePulseBus` / `ParticleAnimator` — should be straightforward.
- No mock for `URLProtocol` — needed for `WeatherManager`, `GoogleCalendarService`.

### CI gap

Per CLAUDE.md: "No CI yet." Even with 41 test files registered, they only run when the user manually presses Cmd+U. **Wiring up GitHub Actions to run `xcodebuild test` on every push** would convert latent test value into actual regression coverage. ~2h one-time setup.
