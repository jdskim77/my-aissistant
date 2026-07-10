# Audit — Theme system + WCAG contrast
**Run:** /overnight 2026-05-04 pass 3
**Files:** [ColorTheme.swift](MyAIssistant/Theme/ColorTheme.swift) (130 lines), [ThemeManager.swift](MyAIssistant/Theme/ThemeManager.swift) (439 lines), [AppColors.swift](MyAIssistant/Theme/AppColors.swift) (99 lines).

## Theme inventory

**The codebase ships 9 themes**, not the 5 documented in CLAUDE.md:

| # | Theme | Mode | Documented in CLAUDE.md? |
|---|---|---|---|
| 1 | indigo | light | ❌ |
| 2 | natural | light (default) | ✅ |
| 3 | ocean | light | ✅ |
| 4 | paper | light | ❌ |
| 5 | accessible | light (high contrast) | ✅ as "High Contrast" |
| 6 | midnight | dark (true black, OLED) | ✅ |
| 7 | twilight | dark | ✅ |
| 8 | slate | dark | ❌ |
| 9 | accessibleDark | dark | ❌ |

**Doc drift:** CLAUDE.md says 5 themes; code has 9. Either CLAUDE.md is stale OR the 4 extra themes (indigo, paper, slate, accessibleDark) are dev-only and shouldn't ship.

## Token surface — strong

Each `ColorTheme` instance defines **30 named tokens** across these groups:
- Backgrounds & surfaces: `background, surface, card, border` (4)
- Accents: `accent, accentWarm, accentLight, gold, coral, skyBlue` (6)
- Text: `textPrimary, textSecondary, textMuted` (3)
- Check-in slots: `morning, noon, afternoon, night` (4)
- Status: `overdueRed, overdueBg, completionGreen` (3)
- Chat: `userBubbleText, aiBubble, aiBubbleText, aiBubbleBorder` (4)
- Checkbox: `checkboxHigh, checkboxMedium, checkboxLow` (3)
- Error/Warning: `error, errorBg, warning` (3)

All themes override all 30 tokens — no fallback inheritance. Good architecture: a new theme is exhaustively defined or the compiler complains.

`ColorTheme.isDark: Bool` lets views branch on light-vs-dark for things like elevation/shadow color.

## Findings

### F1. (High) — Doc drift: CLAUDE.md says 5 themes, code has 9
[CLAUDE.md](CLAUDE.md) (project-level) lists 5: Natural, Ocean, High Contrast, Midnight, Twilight. Reality has 4 more: indigo, paper, slate, accessibleDark.

**Implications:**
- New contributor reads CLAUDE.md, assumes 5 themes — won't update the 4 hidden ones when adding a token, breaking those themes silently.
- App Store screenshot session may miss showing 4/9 of the themes.
- User-facing theme picker — does it expose all 9 or only 5? **Need to verify.**

**Action:** decide whether the 4 extras ship or get pruned. If they ship, document them. ~10 min decision + doc update.

### F2. (High) — No WCAG contrast verification in source
The 30 tokens are hex literals in the theme constructors. Without an automated check, there's no guarantee:

- `textPrimary` on `background` meets WCAG 2.2 AA contrast 4.5:1 across all 9 themes.
- `textSecondary` on `surface` meets 4.5:1.
- `coral` on `coral.opacity(0.06)` (the safety bubble) meets 4.5:1 in all themes including the dark ones.
- `accent` on `accentLight` (chat send button etc.) meets contrast.

**Action:** introduce a test that iterates every theme and asserts contrast for the canonical text-on-bg pairs. Use a small Swift contrast-ratio helper:

```swift
func contrastRatio(_ a: Color, _ b: Color) -> Double { ... }

@Test
func test_textPrimary_on_background_meets_AA_contrast() {
    for theme in ThemeManager.allThemes {
        #expect(contrastRatio(theme.textPrimary, theme.background) >= 4.5)
    }
}
```

**Cost:** ~3h (helper + tests for ~12 critical pairs across 9 themes).

### F3. (High) — Twilight theme coral contrast unverified
The chat-side and check-in safety bubble uses `coral.opacity(0.06)` background with `coral` (full) accents. Pass 2 audit flagged that Twilight theme's coral is `#FB923C` (orange) — at 0.06 opacity on dark surface this may be invisible.

**Action:** explicit visual check on Twilight theme. Either render to screenshot or boot the app under Twilight and trigger a safety bubble.

### F4. (Medium) — `isDark` is a property, not derivable from system colorScheme
`ColorTheme.isDark: Bool` is set per-theme (line 22). This means views that branch on dark-vs-light use the THEME's notion of dark, not iOS's system `@Environment(\.colorScheme)`. If a user sets system to dark mode but picks a light theme, `colorScheme` says dark but `isDark` says light. Views that only check `isDark` may render legibly but views that check `colorScheme` may not.

**Action:** audit which views check which. Standardize on `theme.isDark` (the user's explicit choice trumps system) OR document the asymmetry.

### F5. (Medium) — Color hex literals interpolated, not validated
`Color(hex:)` extension in [AppColors.swift:4-25](MyAIssistant/Theme/AppColors.swift#L4) silently falls back to `(0,0,0)` for malformed input. A typo in a theme constructor (e.g. `"#FFFF"` 4 chars instead of 6) renders black with no error. Compile-time enforcement isn't possible with strings, but a startup-time audit could check.

**Action:** add a `#if DEBUG` startup assertion that every theme's hex strings are 6 or 8 chars. ~15 min.

### F6. (Medium) — No `Increase Contrast` system setting check
iOS users can enable Settings → Accessibility → Display → Increase Contrast. SwiftUI exposes this via `@Environment(\.accessibilityShowButtonShapes)` and `@Environment(\.legibilityWeight)`. No view in the audit appears to consult these. So users with Increase Contrast on get the same coral/grey-on-cream rendering as everyone else.

**Action:** add an Increase-Contrast pass: when enabled, swap to `accessible` / `accessibleDark` automatically OR boost the contrast of the current theme's borders/text.

### F7. (Medium) — Reduce Transparency not checked
Similar to F6. Users with Reduce Transparency on still see the `coral.opacity(0.06)` safety bubble, which is mostly invisible against background.

**Action:** when `@Environment(\.accessibilityReduceTransparency)` is true, render the safety bubble background as `coral.opacity(1.0)` (full coral fill).

### F8. (Low) — No theme-switching animation
ThemeManager.themeID UUID changes on every theme switch (per CLAUDE.md). Views attach `.id(themeManager.themeID)` to force re-render. This is a hard cut. A 200ms cross-fade would feel less jarring.

**Cost:** ~30 min.

### F9. (Informational) — `ColorTheme` struct is `@Sendable`-friendly
Pure value type with `Color` properties (which are `Sendable` since iOS 17). No mutation-in-place patterns. Theme switching = construct new ColorTheme + assign. **Sendable-clean.**

## What's NOT covered by this audit

- Per-pixel contrast measurements: this audit can't measure rendered contrast; it can only flag missing infrastructure.
- WCAG large-text rules (3:1 instead of 4.5:1) for headings.
- Theme behavior under iOS Dynamic Island / Live Activities.
- Theme behavior in widgets.

All of these need device + visual verification.

## Recommended fix order

1. **F1 — reconcile CLAUDE.md 5 vs code 9 themes** (10 min).
2. **F2 — contrast-ratio test harness** (3h). Highest leverage — catches future regressions automatically.
3. **F3 — Twilight coral safety bubble visual check** (15 min on device).
4. **F6 + F7 — Increase Contrast / Reduce Transparency env checks** (~1.5h).
5. **F4 — colorScheme vs isDark audit** (~30 min).
6. **F5 — hex validation startup assertion** (15 min).
7. **F8** — opportunistic.

Total: ~5-6h to hit AA contrast confidence across all 9 themes plus accessibility-setting support.
