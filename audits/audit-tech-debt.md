# Audit — TODO / FIXME / doc-comment gaps
**Run:** /overnight 2026-05-04

## Headlines

| Item | Count | Read |
|---|--:|---|
| `// TODO:` markers | 0 | **clean** |
| `// FIXME:` markers | 0 | **clean** |
| `// XXX:` / `// HACK:` | 0 | **clean** |
| `// BUG-XX` historical refs | many | context-only (prior QA fixes); not pending work |
| Managers without leading doc-comment | 14 of 26 | 54% gap |
| Services without leading doc-comment | 13 of 27 | 48% gap |

## TODO / FIXME

**There are no rotting TODOs in the production source.** Comments referencing `BUG-XX` are historical context for fixes already shipped (e.g. "BUG-05 fix: foreground evaluation must fire on every…") — they document why the fix exists, not a pending defect.

This is a strong signal of code hygiene. Either the team consistently closes TODOs or they go in the audit handoff docs (like this one) instead of the source.

## Top-level doc-comment gaps

Per the project's pattern, each Manager / Service file should open with a `///` block explaining the type's purpose, when to use it, and any non-obvious invariants. The well-documented ones (e.g. `BalancePulseBus.swift`) have ~15 lines of header that orient a new reader instantly. Missing headers mean the next contributor reads the type from the inside out.

### Managers without top-level doc (14)

| File | Lines | Suggested header |
|---|--:|---|
| BackgroundTaskManager.swift | 250+ | "Registers and runs the four BGTasks: daily snapshot, weekly review, calendar sync, nudge evaluation. Each task has its own expiration handler; `UIApplication.backgroundTaskIdentifier` ordering matters." |
| ChatManager.swift | 805 | "Chat send pipeline. Owns conversation persistence, response-tag parsing, calendar-action execution, and the crisis-classifier gate. `shouldSendToAI` is the canonical filter for outbound history." |
| CheckInBehaviorEngine.swift | 464 | "14-day adaptive completion stats. Drives notification frequency and check-in suggestions. Math-heavy; updates are append-only on completion events." |
| CheckInManager.swift | ~ | "Check-in lifecycle CRUD. Wraps SwiftData writes for `CheckInRecord`. AI summary is generated downstream by `DailyRecapGenerator`, not here." |
| GreetingManager.swift | ~ | "App-launch greeting with 1-hour cooldown. Pulls AI-generated copy when subscription tier permits." |
| HabitManager.swift | 168 | "Habit CRUD + completion logging. Mirrors `TaskManager` for the BalancePulse contract — practical/untagged habits emit a neutral pulse." |
| InsightEngine.swift | 324 | "Pattern detection for the Compass surface. Refuses claims below statistical-significance thresholds." |
| NotificationManager.swift | ~ | "All `UNUserNotification` registrations: check-in reminders, task reminders, habit reminders, NUDGE_CATEGORY actions (Accept/Dismiss/Snooze/Silence)." |
| ParticleAnimator.swift | 475 | "Queued particle-flight animations. Suppression window prevents same-dimension re-fire from tap + bus pulse. Haptic dedup uses `lastHapticAt`." |
| PatternEngine.swift | ~ | "Streak math, completion rate, mood trend, weekly AI review. Statistical-honesty constraint: refuse claims under sample-size threshold." |
| TaskManager.swift | ~ | "Task CRUD. Owns the BalancePulse contract: scored-dim → normal pulse, otherwise neutral pulse with `dimension: .practical, isNeutral: true, points: 1`." |
| UsageGateManager.swift | ~ | "Tier-based limit enforcement. Free: 10 chat/month, 5 check-ins/week. Pro: unlimited. Counts reset monthly/weekly via `UsageTracker.resetIfNeeded()`." |
| WatchSyncManager.swift | 329 | "WCSession bridge. Pushes schedule + API key + check-ins + tasks to watch; receives task completions back." |
| WisdomManager.swift | ~ | "Daily wisdom quote selection. Static curated set; rotation is deterministic by date." |

### Services without top-level doc (13)

Notably:
- `SubscriptionManager.swift` (StoreKit 2 — important context)
- `APIClient.swift` (network actor)
- `KeychainService.swift` (security boundary — needs explicit doc)
- `AIPromptBuilder.swift` (the file that defines all coach behavior — would benefit from a "load-bearing" warning)
- `AnthropicProvider.swift` / `OpenAIProvider.swift` / `AIProviderFactory.swift` (provider abstraction)
- `EdgeVoiceProvider.swift` / `AppleVoiceProvider.swift` / `SpeechRecognizer.swift` / `SpeechSynthesizer.swift`
- `VariedGreetingBuilder.swift`

## Recommended fix

Add 1 doc-comment header per Manager/Service. Each is 5-15 lines. Total = 27 files × ~10 min reading + writing = **~4–5h of focused work**.

This is the single highest-ROI maintenance task in the catalog. New contributors (and future-you) read the file header to orient. Without it, every code-spelunking session starts from scratch.

**Priority order:**
1. Managers that own load-bearing contracts: `ChatManager`, `TaskManager`, `HabitManager`, `ParticleAnimator`, `PatternEngine`, `BackgroundTaskManager`. (~2h)
2. Services with security implications: `KeychainService`, `AIPromptBuilder`, `AnthropicProvider`. (~1h)
3. Everything else, opportunistically.

## What's NOT a problem

- No dead code markers.
- No commented-out blocks.
- No `print()` debugging left behind.
- No "remove this once X" loose ends — the BUG-XX historical comments are explicit about being fixes, not deferrals.

The codebase is reasonably tidy. The doc-gap is the real maintenance debt; the rest is low-noise.
