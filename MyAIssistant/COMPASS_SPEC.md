# Life Compass — Design Specification

> Single source of truth for the Compass/Balance feature. All scoring, UX, and architecture
> decisions are documented here. Reference this before modifying any Compass-related code.

---

## 1. Concept

The Life Compass helps users maintain intentional balance across four dimensions of their life. It doesn't judge — it reveals patterns so users can tune their allocation of time and energy.

**Core insight:** Balance isn't about maxing every area. It's about intentional allocation that matches your current life season.

**Philosophical foundations:**
- Wheel of Life (coaching methodology)
- PERMA model (Seligman — positive psychology)
- WHO-5 Well-Being Index
- Self-Determination Theory (Deci & Ryan)
- Designing Your Life (Burnett & Evans — energy/engagement tracking)

---

## 2. The Four Dimensions

| Dimension | Icon | Color | What It Includes |
|-----------|------|-------|-----------------|
| **Physical** | figure.run | #4CAF50 (green) | Exercise, sleep, nutrition, healthcare, sports, yoga (as exercise) |
| **Mental** | brain.head.profile | #2196F3 (blue) | Learning, reading, creative work, problem-solving, courses, writing |
| **Emotional** | heart.fill | #E91E63 (pink) | Relationships, social time, fun, self-care, therapy, celebrations |
| **Spiritual** | sparkles | #9C27B0 (purple) | Meditation, gratitude, service, helping others, volunteering, nature, purpose |

**Practical** (wrench icon, #78909C) exists as a task category but is **unscored** — errands and admin don't contribute to life balance evaluation.

### Ambiguity Rule
Some activities span dimensions (yoga = Physical or Spiritual, journaling = Mental or Emotional). The AI suggests a dimension based on keywords and learned preferences, but the **user confirms with one tap**. Over time, the system learns each user's personal interpretation.

---

## 3. Scoring Model (3-Signal Composite)

Each dimension receives a score from **0 to 10** per week, computed from three independent signals:

### Signal Weights

| Signal | Weight | Range | What It Measures |
|--------|--------|-------|-----------------|
| **Activity** | 30% | 0-10 | Effort-weighted task completion vs personal target |
| **Satisfaction** | 40% | 0-10 | User's self-rated satisfaction from check-ins (1-5 mapped to 2-10) |
| **Consistency** | 30% | 0-10 | How many days this week had activity in the dimension (days/7 × 10) |

### Composite Formula

```
dimension_score = activity × 0.30 + satisfaction × 0.40 + consistency × 0.30
```

### Signal Details

**Activity Score:**
```
effort_points = sum(task.effort.points) for completed tasks tagged with this dimension
activity_score = min(10, effort_points / personal_target × 10)
```
- Default personal target: 10 effort points per dimension per week
- User can customize targets per dimension via settings

**Satisfaction Score:**
```
mean_rating = average(check_in_satisfaction_ratings) // 1-5 scale
satisfaction_score = mean_rating × 2 // maps 1-5 to 2-10
```
- Default (no check-in data): 5.0 (neutral — absence shouldn't penalize)
- Multiple check-ins per week: averaged

**Consistency Score:**
```
active_days = count(distinct weekdays with completed dimension-tagged tasks)
consistency_score = active_days / 7 × 10
```

### No-Data Default
When the user has zero data for the week (new user, start of week), all dimensions default to 5.0 (neutral balanced) so the Compass looks balanced rather than empty. Once any data arrives, real scores take over.

---

## 4. Balance Score

Measures how **evenly distributed** the four dimension scores are.

```
balance_score = max(0, min(10, mean - 1.5 × stdev))
```

| Balance Score | Meaning |
|--------------|---------|
| 8-10 | Highly balanced — all dimensions similar |
| 5-7 | Moderately balanced — some variation |
| 2-4 | Imbalanced — one or more dimensions neglected |
| 0-1 | Severely imbalanced — one dimension dominates |

**Key insight:** A user with all 5s (balance=5.0) scores higher than a user with 10, 10, 1, 1 (balance≈1.2). This rewards breadth over depth.

The Harmony Score displayed in the UI is `Int(balance_score × 10)` for a 0-100 percentage display.

---

## 5. Balance Streak

Consecutive weeks where **all four dimensions score >= 3.0 out of 10**.

- Floor of 3.0 is intentionally low — it means "not completely neglected"
- Current week with no data: skipped (doesn't break streak)
- Past week with no data: breaks streak (early exit)
- Maximum lookback: 52 weeks

---

## 6. Check-In System

### Evening Check-In (3-step flow)

**Step 1: Dimension ratings** — User rates satisfaction (1-5) for each of the four dimensions. Per-dimension ratings feed the Satisfaction signal.

**Step 2: Energy slider** — "How did today feel overall?" Slider from -3 (Drained) to +3 (Energized). Emoji changes in real-time (😩→😔→😐→🙂→😊→😄→🔥). Skip available.

**Step 3: Confirmation** — Shows summary, auto-dismisses after 1.5 seconds.

### Data Model: DailyBalanceCheckIn

| Field | Type | Purpose |
|-------|------|---------|
| dimensionRaw | String | Best energy dimension (legacy / summary) |
| energyRating | Int? | -3 to +3 daily energy level |
| physicalSatisfaction | Int? | 1-5 rating |
| mentalSatisfaction | Int? | 1-5 rating |
| emotionalSatisfaction | Int? | 1-5 rating |
| spiritualSatisfaction | Int? | 1-5 rating |

Multiple check-ins per day supported (morning, midday, afternoon, evening).

---

## 7. Dimension Learning

The system learns which dimensions users associate with specific activities.

### How It Works

1. **First time:** AI suggests dimension based on keyword matching (e.g., "yoga" → Physical)
2. **User overrides:** User taps "Spiritual" instead → preference recorded
3. **Second time:** AI suggests "Spiritual" for yoga (learned preference, 100% confidence)
4. **Pre-selection:** At confidence >= 60% with 2+ data points, the chip is pre-selected (not just suggested)

### Data Model: UserDimensionPreference

| Field | Type | Purpose |
|-------|------|---------|
| keyword | String | Lowercased activity keyword |
| dimensionRaw | String | User's preferred dimension |
| confirmCount | Int | Times tagged with this dimension |
| totalCount | Int | Times tagged with any dimension |
| confidence | Double | confirmCount / totalCount (computed) |

### Suggestion Priority (DimensionSuggester)

1. **Learned preferences** (confidence >= 0.6, totalCount >= 2) → pre-select chip
2. **Keyword matching** (static keyword lists) → sparkle chip suggestion
3. **Category fallback** (TaskCategory → LifeDimension mapping) → sparkle chip suggestion

### Visual UX

- **Low confidence:** Sparkle chip appears above the picker row. Nothing pre-selected.
- **High confidence:** Chip auto-pre-selected with sparkle icon inside. User sees the AI "knows."
- **Ambiguous (variance detected):** Two common choices get half-filled indicator.

---

## 8. Season Goals

A 4-week focus on one dimension. Users pick a dimension and set an intention.

| Field | Value |
|-------|-------|
| Duration | 28 days |
| Dimensions | Any of the 4 scored |
| Intention | Free-text (e.g., "Exercise 3x/week") |
| Effect | Nudges weighted toward this dimension |
| Progress | Elapsed days / total days (uses completedAt for early completion) |
| Active check | Includes the entirety of the final day |

### Season Goal View Sections

1. **Hero** — Progress ring, icon, dimension name, intention, date range
2. **Performance card** — This week's 3-signal breakdown (activity, satisfaction, consistency)
3. **Weekly trend** — Last 4 weeks of scores for this dimension
4. **This week's tasks** — Completed tasks tagged with this dimension
5. **AI suggestion** — Context-aware recommendation
6. **End goal early** — Requires confirmation dialog

---

## 9. Nudge System

One suggestion per day for the weakest dimension. Max 1 nudge per day.

### Logic
1. Find the scored dimension with the lowest score this week
2. If an active season goal dimension is lagging (< 0.5), boost its priority
3. Only show if weakest score < 5.0 (out of 10)
4. Suppress after 3 consecutive dismissals
5. Re-engage when user manually logs that activity again at matching interval

### Nudge Dismiss Key
Uses date string format (`yyyy-MM-dd`) — timezone-stable.

### Where It Appears
- **Home screen:** The nudge banner is the only Compass element on Home
- **Compass tab:** Full feature lives here (radar chart, season goals, check-ins, reflection)

---

## 10. Weekly Reflection

Appears Sunday after 5 PM. Shows the Compass radar snapshot + a contextual prompt.

### Prompt Logic
- Strong + weak dimension: "Your [strong] was great, but [weak] fell behind. What would help?"
- Very strong dimension: "Great [strong] week! What made that happen?"
- Very weak dimension: "[weak] was quiet. Intentional, or want to shift?"
- Default: "How balanced did this week feel?"

### Persistence
- Reflection text saved to UserDefaults (keyed by week + yearForWeekOfYear)
- Completion flag saved separately
- Text survives view dismissal and can be re-read

---

## 11. Energy Tracking (Phase 1 — Foundation)

Daily energy slider (-3 to +3) stored alongside check-ins. Currently collected but not yet incorporated into scoring.

### Future Phases

| Phase | What | When |
|-------|------|------|
| **Phase 1** (shipped) | Energy slider in evening check-in, stored per day | Now |
| **Phase 2** | Tag recalled activities with energy rating, per-activity insights | Next |
| **Phase 3** | AI surfaces energy patterns: "Highest-energy days had morning exercise" | After 4 weeks data |

### Resonance Score (future)
A derived metric blending energy trend, activity-energy correlation, and dimension balance. Captures **direction** (improving vs declining), not just state.

---

## 12. Smart Activity Recall (Designed, Not Yet Built)

After the evening check-in, the AI presents 1-3 cards of activities it suspects the user did today but didn't log.

### Confidence Scoring
```
confidence = baseFrequency × dayMatch × recencyBoost × acceptanceRate
```

### Thresholds
- Show if confidence > 60%
- Suppress after 3 consecutive dismissals
- Re-engage when user logs activity at matching weekday pattern

### Duration Tracking
- Rounded pills: 15 / 30 / 45 / 60 min + custom input
- Pre-selected to user's most common duration

---

## 13. Architecture

### Models (SwiftData)
- `DailyBalanceCheckIn` — Per-dimension satisfaction + energy + best dimension
- `SeasonGoal` — 4-week focus goal with progress tracking
- `UserDimensionPreference` — Learned keyword → dimension mappings
- `TaskItem.dimension` — Optional dimension tag on any task
- `TaskItem.effort` — Effort level for activity score weighting

### Schema Version
**V4** — includes all Compass models. Migration plan: V1→V2→V3→V4 (all lightweight).

### Managers
- `BalanceManager` — Scoring, check-ins, nudges, season goals, reflection, AI summary
- `DimensionSuggester` — Keyword + learned preference → dimension suggestion

### Views
- `CompassTabView` — Main tab (replaces Patterns tab)
- `CompassView` — Radar chart with 3-signal breakdown cards
- `CompassInfoSheet` — "How it works" explainer
- `EveningCheckInView` — 3-step check-in flow
- `SeasonGoalView` — Goal creation/management with performance cards
- `WeeklyReflectionView` — Sunday reflection with radar snapshot
- `NudgeBannerView` — Inline nudge card (lives on Home screen)
- `DimensionPickerView` — Reusable chip picker with learning

### Where Things Live
- **Home screen:** Only the nudge banner (actionable, "what should I do?")
- **Compass tab:** Everything else (reflective, "how am I doing?")

---

## 14. What "Good" Looks Like

There is no universal 10/10. Balance is personal.

| Score Range | Meaning | Visual |
|-------------|---------|--------|
| 0-2 | Neglected — no activity in this area | Red zone, nudge triggered |
| 3-4 | Maintenance — some activity but below baseline | Amber, gentle awareness |
| 5-6 | Active — meeting typical engagement | Green, healthy |
| 7-8 | Focused — above baseline, strong investment | Blue/purple, great |
| 9-10 | Immersed — heavy focus (check: is another area suffering?) | Gold, with balance note |

**Healthy profile:**
- All four dimensions at 3+ (nothing neglected)
- Season goal dimension at 6+ (intentional focus working)
- Balance score at 5+ (reasonable balance)
- Energy trend stable or rising

---

## 15. Design Principles

1. **Tune, don't judge.** The Compass reveals patterns. It never says "you're failing."
2. **Weekly rhythm.** Balance is measured weekly, not daily. A Monday focused entirely on work is fine if Tuesday has exercise.
3. **The user's truth.** If they tag yoga as Spiritual, that's correct for them. The system learns, not overrides.
4. **Invisible intelligence.** Learning, suggestions, and nudges happen behind the scenes. The UI stays simple.
5. **Progressive depth.** Daily: just check in. Weekly: see the radar. Monthly: reflect on trends. Power users go deeper; casual users stay surface.
6. **Action over analysis.** Every insight should lead to "here's what you could do." Never pure data without a next step.
