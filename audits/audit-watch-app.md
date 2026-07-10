# Audit — Watch app
**Run:** /overnight 2026-05-04 pass 2
**Scope:** `MyAIssistantWatch Watch App/` — 14 .swift files, 3838 LOC.

## Headline numbers

| Metric | Count | Read |
|---|--:|---|
| Total LOC | 3838 | meaningful surface — not a thin shell |
| Largest files | WatchVoiceChatView (597), WatchConnectivityManager (531), WatchTodayView (464), WatchBalancePulse (431) | |
| Hardcoded `.font(.system(size:))` | 40 | does not use AppFonts |
| `AppFonts.*` uses | **0** | watch is on a separate type system from phone |
| `Task.sleep(nanoseconds:)` | 0 | clean |
| `DispatchQueue.main` | 0 | clean |
| `print()` | 0 | clean |
| `try!` | 0 | clean |

## Findings

### F1. **(HIGH) — Crisis classifier is NOT applied on watch chat path**

`WatchVoiceChatView.sendTextQuery(_ text: String)` ([WatchVoiceChatView.swift:262](MyAIssistantWatch%20Watch%20App/WatchVoiceChatView.swift#L262)) takes user voice transcript or typed text and passes it directly to `claudeService.sendQuery(...)` with **no on-device crisis classifier**.

Compare to:
- iOS chat: `ChatManager.send` runs `KeywordCrisisClassifier.evaluate` BEFORE the LLM call.
- iOS check-in notes: `DailyRecapGenerator` runs the same classifier on every note.
- Watch chat: nothing.

**Threat scenario:** a watch-only user (or a user who happens to use the watch for a particular conversation) types a crisis message. It goes to Anthropic. The model responds without safety routing. No safety resources surfaced, no breadcrumb, no fail-closed.

This is the **same severity class** as the chat-side leak we just fixed in iOS (BUG-01/02 of the chat-bubble QA pass) — except the leak is by-design here, not via a missing filter.

**Fix path (no schema change required):**

1. Port `KeywordCrisisClassifier` to the watch target (or share via a Swift package). The class is a pure-Swift struct with no UIKit dependencies.
2. Add a precheck in `sendTextQuery` before the API call.
3. On flag: surface `SafeResourceCopy` text inline (the watch already has multi-line text; render the same `findahelpline.com` link).
4. Log via `os.log` for parity with iOS's breadcrumb.

**Estimated cost:** 2–3h. Mostly file plumbing + a watch UI variant of the safety bubble.

### F2. **(MEDIUM) — Watch text input not sanitized**

`WatchClaudeService.sendQuery(prompt:scheduleContext:apiKey:)` interpolates the user's prompt directly into the request body. iOS counterparts use `text.sanitizedForPrompt`. The watch path does not.

**Impact:** smaller than F1 — sanitization is defense-in-depth, not the safety boundary. But same principle: the watch shouldn't have weaker guarantees than the phone.

**Fix:** import `String+SanitizedForPrompt` extension into the watch target. 5 min + recompile.

### F3. (MEDIUM) — Watch Anthropic call hits the API directly, NOT via the backend proxy

[WatchClaudeService.swift:6](MyAIssistantWatch%20Watch%20App/WatchClaudeService.swift#L6): `private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!`

The iOS app routes through `thrivn-backend/` (Cloudflare Worker proxy) for the Pro/Student/PowerUser tiers (per CLAUDE.md). The watch goes direct.

**Implications:**
- The backend's safety controls (rate limiting, abuse detection, model-pin enforcement, BYOK key isolation) don't apply on watch.
- API key is on the watch in Keychain. If the user is BYOK-only, that's their key — fine. If they're a paid-tier user expecting backend-routed calls, the watch's direct call is inconsistent.
- Watch usage doesn't show up in the backend's `usage_logs` table — billing/analytics blind spot.

**Fix path:** route watch calls through the same `ThrivnBackendService` that iOS uses for paid tiers. ~half-day refactor including watch HTTP client.

### F4. (Low) — Watch lacks AppFonts integration

40 hardcoded `.font(.system(size: N))` literals. Watch typography is intentionally different from phone (smaller screen, different typographic scale), but the project does not have a `WatchFonts` equivalent of `AppFonts`. Each font size is decided ad-hoc per view.

**Impact:** Dynamic Type on watch (yes, watchOS supports it) does not scale text consistently. Size accessibility users on watch see fixed-size text.

**Fix idea:** create `WatchFonts.swift` with `body(_:)`, `heading(_:)`, `caption(_:)` that wrap `UIFontMetrics.default.scaledValue` like AppFonts does. Migrate the 40 sites. ~1.5h.

### F5. (Informational) — No `WatchCrisisClassifier` or shared safety code

iOS has two crisis-related files (`CrisisClassifier.swift` + `KeywordCrisisClassifier.swift` + `SafeResourceCopy.swift`). The watch target has neither. F1's fix is the right time to introduce a shared "Safety" module, even if it's just three .swift files compiled into both targets.

### F6. (Informational) — Watch tests are 1 file, no coverage

Only `MyAIssistantWatch_Watch_AppTests.swift` exists. The watch surface (3838 LOC) has effectively no test coverage. Not a fix-tonight item, but a long-term gap.

## What looks good

- **WatchConnectivityManager (531 LOC)** — substantial size but clean of don't-do violations.
- **No print() / try! / Thread.sleep** — discipline matches iOS side.
- **No DispatchQueue.main misuse** — modern concurrency on watch.

## Recommended fix order

1. **F1 — port crisis classifier to watch** (2–3h). Same severity class as the chat-side fix we just shipped on iOS.
2. **F2 — sanitize watch input** (5 min). Bundled with F1.
3. **F3 — route watch through backend proxy** (half day). Higher cost, lower urgency. Do when convenient.
4. **F4 — WatchFonts migration** (1.5h). Quality-of-life.
5. **F6 — watch test coverage** — long-term project.

## Critical takeaway

**Today's safety leak fix on iOS chat (BUG-01/02 of the chat-bubble QA pass) does NOT cover the watch.** The watch chat path has no crisis classifier and no sanitization. A watch-only user with crisis content gets it relayed straight to Anthropic.

This is the highest-leverage finding in this audit pass. Recommend treating it as a **P0 follow-up** to the iOS chat fix.
