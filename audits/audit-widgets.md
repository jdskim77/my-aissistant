# Audit — Widgets
**Run:** /overnight 2026-05-04 pass 2
**Scope:** `MyAIssistantWidgets/` — 5 .swift files, 578 LOC.

## What ships in widgets

| Widget | Source | Surface |
|---|---|---|
| TodayProgressWidget | TodayProgressWidget.swift (251) | Lock + Home + StandBy |
| NextCheckInWidget | NextCheckInWidget.swift (177) | Lock + Home |
| StreakWidget | StreakWidget.swift (88) | Lock + Home |

## App Group surface (the privacy boundary)

[WidgetData.swift](MyAIssistantWidgets/WidgetData.swift) defines what crosses the App Group from main app → widgets. Inventory:

```swift
struct WidgetData: Codable {
    let tasksCompleted: Int      // count only
    let tasksTotal: Int          // count only
    let topPending: [WidgetTask] // ⚠️ task titles
    let streakDays: Int          // count only
    let streakActive: Bool
    let quoteText: String?       // curated
    let quoteAuthor: String?     // curated
    let updatedAt: Date
}

struct WidgetTask: Codable {
    let title: String            // ⚠️ user-typed title
    let priority: String
    let time: String?
}
```

## Findings

### F1. (Medium-Low) — Task titles surface on Lock Screen / StandBy
`topPending[].title` is the user's task title verbatim. Lock Screen widgets are visible to anyone holding the device. StandBy is an always-on bedside display.

**Threat scenarios:**
- Title "Therapy with Dr. Smith 4pm" → visible to anyone glancing at the phone.
- Title "Meet with [private]" → same.
- Title "Confess to [name]" → same.

**iOS 17+ has built-in countermeasures:** Lock Screen widgets respect `.privacySensitive()` automatically when the device is locked. Need to verify the widget views opt into this.

**Action:** verify each widget's task-title rendering wraps the title in `.privacySensitive()` so the title redacts to a "•••" placeholder when locked. Quick check below.

**Fix cost:** ~30 min to verify + add `.privacySensitive()` if missing.

### F2. (Low) — Widget uses `try?` on persistence
[WidgetData.swift:35-44](MyAIssistantWidgets/WidgetData.swift#L35) — `try? decoder.decode` on read, `try?` on `data.write(to:)`. Per the project rule: *"NEVER `try?` on persistence or network — silent data loss."*

**Mitigating factor:** widget data is regeneratable. The main app rewrites it on every save event. A failed widget read just means the widget shows stale data until the next refresh — not a data-loss event.

**Fix cost:** ~10 min to add proper error logging via `os.log`. Low priority.

### F3. (Low) — 26 hardcoded `.font(.system(size:))` in widgets, 0 `AppFonts` usage
Same pattern as the watch app. Widgets render at fixed sizes per WidgetFamily (systemSmall/Medium/Large), so Dynamic Type is less impactful, but iOS does support Dynamic Type on widgets. Hardcoded sizes mean accessibility-text users see a fixed widget regardless.

**Fix cost:** ~1h to introduce `WidgetFonts.swift` (similar to `AppFonts`) and migrate.

### F4. (Informational) — App Group ID matches entitlement
`appGroupID = "group.com.myaissistant.shared"` matches `MyAIssistantWidgets.entitlements`. Check passes.

### F5. (Informational) — Widget reads only the curated WidgetData JSON, not SwiftData
The widget does NOT open the SwiftData store. It reads only the App Group JSON the main app writes. This is the right architecture:
- No risk of widget triggering migration
- No risk of widget reading crisis-flagged ChatMessage
- Smaller widget binary

This separation is a privacy + perf win. **Keep it.**

### F6. (Informational) — No chat content, no check-in notes, no AI responses in widget
**Verified clean:** the widget data surface is minimal (counts + task titles + curated quotes). Crisis content cannot reach the widget by design.

## Recommended fix order

1. **F1 — verify `.privacySensitive()` on task-title widget rendering** (30 min). Quick spot-check; tighten if missing.
2. **F2** — `try?` → proper error logging (10 min, opportunistic).
3. **F3** — `WidgetFonts` migration (1h, polish).

## Critical takeaway

Widgets are well-architected. The data boundary is small and curated; sensitive content (chat, crisis text) cannot reach the widget by design. The only privacy concern is task titles on Lock Screen — verify `.privacySensitive()` wrapping and you're done.
