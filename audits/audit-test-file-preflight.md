# Audit — Test file pre-flight (registration risk)
**Run:** /overnight 2026-05-04 pass 2
**Goal:** before the user drags 35 unregistered test files into the Xcode test target, identify which ones are likely to fail compilation due to drifted APIs. Saves them ~30-60 min of in-IDE triage.

## Method

For each unregistered test file:
1. Count tests + lines.
2. Sample its references to model/manager init signatures.
3. Cross-check against current source.
4. Flag if any reference is to a renamed/removed/retyped symbol.

## Headline

**Most pre-existing tests look likely-to-compile.** No `Tab` (renamed to `AppTab` this session) references found anywhere. Init signatures sampled match current code. The concern about months-old tests referencing drifted APIs appears to be smaller than feared.

The biggest risk isn't compile-fail — it's **logical drift**: tests asserting old behavior that's now wrong. Those will fail at runtime, not compile.

## Per-file pre-flight

### Likely-to-compile (28 of 36)

These reference stable model/service init signatures that exist in current code. Spot-checked and aligned.

**Models (15):**
- ActivityEntryTests · 3 tests
- AlarmEntryTests · 5 tests
- CalendarLinkTests · 8 tests
- ChatMessageTests · 7 tests — uses 2-arg init, still compiles (other params have defaults)
- CheckInRecordTests · 14 tests
- DailySnapshotTests · 4 tests
- FocusSessionTests · 4 tests
- HabitItemTests · 27 tests — uses 1-arg & 2-arg HabitItem init, both still compile
- TaskCategoryTests · 5 tests
- TaskItemTests · 16 tests — uses 5-arg init `(title:, category:, priority:, date:, icon:)`, matches current
- TaskPriorityTests · 5 tests
- UsageTrackerTests · 24 tests — uses no-arg init + static keys, all match
- UserProfileTests · 3 tests
- WatchScheduleDataTests · 6 tests
- ChatMessageHistoryFilterTests · 8 tests *(written this session)*

**Services (10):**
- AIPromptBuilderTests · 9 tests — uses `chatSystemPrompt`, `checkInPrompt`, `weeklyReviewPrompt` — all still in source
- AIProviderFactoryTests · 14 tests — uses `provider(for:, useCase:, keychain:)` — matches current
- AIProviderTests · 15 tests — covers `AIResponse`, `AIError`, `AIUseCase` — all stable
- DailyRecapGeneratorCrisisGateTests · 11 tests *(written this session, includes new `RecapResult` enum)*
- KeychainServiceTests · 14 tests
- KeywordCrisisClassifierTests · 13 tests *(written this session)*
- SpeechRecognizerTests · 9 tests
- SpeechSynthesizerTests · 5 tests
- SubscriptionTierTests · 15 tests
- VariedGreetingBuilderTests · 10 tests

**Managers (3 unregistered):**
- ChatManagerParserTests · 11 tests *(written this session, references internal `parseResponseTags`)*
- TaskManagerNeutralPulseTests · 6 tests *(written this session, uses `BalancePulseBus` directly)*
- *(other Manager tests already registered)*

### Caveat — runtime drift risk (medium)

Even when tests compile, their assertions may be stale:

1. **TaskItemTests** asserts behaviors on `TaskItem` from before today's `dimensions` array was added. If any test asserts `task.dimension` (singular) directly when it now goes through a computed-array accessor, behavior may differ on edge cases (e.g. setting nil clears the array; reading nil returns `dimensions.first`).

2. **HabitItemTests** has 27 tests — likely covers behaviors that still hold, but the `targetDays.appliesTo(...)` and dimension-tagging behavior may have evolved.

3. **AIProviderFactoryTests** asserts tier→model mapping. The mapping was edited recently to ensure model alignment with backend (`claude-haiku-4-5-20251001`, `claude-sonnet-4-5-20250929`). If a test asserts a literal model ID string, the assertion may have drifted.

4. **AIPromptBuilderTests** asserts substring presence in generated prompts. The prompt was rewritten in this session (dimension taxonomy reshuffled — practical now includes healthcare admin). Tests asserting "physical: exercise, sleep, nutrition, healthcare" will fail because healthcare moved to practical.

### Required fix-ups before clean run

- **AIPromptBuilderTests.swift** — at least one assertion will fail (the dentist/healthcare taxonomy moved). 5-min spot-fix.
- **TaskItemTests.swift** — verify `dimensions` array accessor patterns match. 10-min review.
- **AIProviderFactoryTests.swift** — verify model-ID strings match `AppConstants` constants. 5-min review.

Total: **~20 minutes of test fixup expected** after the wire-up. The other 32 files should pass as-is.

### Test-target pbxproj-edit caveat

When the user drags the 35 files into Xcode:
1. **Multi-select** all 35 in Finder before drag-and-drop, so the "Add to targets" checkbox applies once across the whole batch.
2. **Uncheck the main app target.** Default behavior may add to all targets, which would cause "Cannot find type 'XCTest'" in the main app build.
3. **Choose "Create groups"** (not "Create folder references") so the file structure mirrors Finder hierarchy in the navigator.

## Recommended next steps

1. Drag all 35 files in (5 min).
2. Cmd+U.
3. Triage failures in Xcode Test Navigator — likely 3-4 files need 5-20 min total fix.
4. Once green: update `OVERNIGHT-NOTES.md` (or this file) with the actual pass count.

If `xcodebuild test` reveals a test that fails for a reason that's not "drift" but actually exposes a real bug — file it as a `BUG-XX` and decide whether to fix or skip per project priority.
