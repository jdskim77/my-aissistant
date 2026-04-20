# Life Balance — Design V2

Proposal to make the compass feel **inspirational, not punishing**, and to
clarify the roles of the **Home** and **Compass** screens.

Three problems with today's design:
1. `balance = mean - 1.5·stdev` can collapse to near-zero; a user already
   feeling off gets a 12/100 "you're broken" score.
2. Home and Compass show the same weekly average. Home has no sense of
   "what did I just do today?"
3. Completing a task makes a bar twitch, but the user can't feel the bar
   *filling up* toward anything concrete.

---

## 1. The score never drops below 30

### Floor + power curve

Replace the linear 0–100 mapping with a curve that asymptotes to 30:

```
display = 30 + 70 · (raw / 10) ^ 0.7      // raw is the 0–10 balance score
```

Anchor points:

| raw (0–10) | current display | new display | stage label |
|------------|-----------------|-------------|-------------|
| 0.0        | 0               | **30**      | *Seedling*  |
| 1.5        | 15              | 42          | *Seedling*  |
| 3.0        | 30              | 58          | *Rooting*   |
| 5.0        | 50              | 75          | *Flowing*   |
| 7.0        | 70              | 86          | *Thriving*  |
| 10.0       | 100             | 100         | *Radiant*   |

Why a curve, not just a floor: a pure floor (`max(30, raw·10)`) creates a
flat dead zone from 0 → 3. The power curve keeps every action meaningful —
a user at raw 1.0 ticks up to 50, not stays stuck at 30.

Why 30, not 0: 30 represents "you're here, you're trying, you have a
reading" — the floor is the act of showing up. The score only ever *adds*
from there.

### Soften the imbalance penalty

Today: `mean − 1.5·stdev`. A user with 8/8/8/2 drops to ~5.4 raw.
Proposed: `mean − 0.5·stdev + 0.5·min_dim_weight`, where
`min_dim_weight = min(1, lowest_dim / 3)` — rewards paying any attention to
your weakest dimension instead of punishing imbalance outright.

Net effect on 8/8/8/2: raw goes from 5.4 → 6.8 → display **83**.
Net effect on 8/8/8/0: raw goes from 5.4 → 5.4 → display **75**.
Imbalance still costs something, but the cliff is gone.

### Stage language replaces color alarm

Drop the red/yellow/green. Use warm earth tones plus a stage label:

- 30–45  **Seedling** — terracotta
- 45–60  **Rooting** — amber
- 60–75  **Flowing** — teal
- 75–90  **Thriving** — emerald
- 90+    **Radiant** — gold

Never red. The lowest state is still a warm color. The label carries the
signal; the number stops feeling like a grade.

---

## 2. Home ≠ Compass

### Compass screen = "where am I overall"

This is the **weekly review** surface. Keep what's there:
- Radar of the 4 dimensions (weekly composite 0–10)
- Harmony number (new 30–100 display)
- Stage label + earth color
- Dimension cards with activity/satisfaction/consistency breakdown
- Streak, season goal, reflection

New additions:
- A tiny 4-week sparkline on each dimension card (shows trajectory, not just
  snapshot).
- A "Today's contribution" strip at the top showing how many points landed
  today, per dimension — creates a bridge back to Home without duplicating it.

### Home screen = "am I moving today"

This is the **momentum** surface. Rewrite BalancePulseCard around **today's
fill**, not the week's average.

```
┌─────────────────────────────────────────────────────┐
│  LIFE BALANCE · Flowing 75                       ▾  │
│                                                     │
│   ▓█    ░█    ░▓    ░▓     ← today's fill (solid)   │
│   ▓█    ▓█    ▓█    ▓█     ← weekly avg (ghost)     │
│   ◯    ◯    ◯    ◯                                  │
│  Body  Mind  Soul Hustle                            │
│                                                     │
│  Today +2 Body, +1 Mind — nudging your compass up   │
└─────────────────────────────────────────────────────┘
```

Two bars stacked in the same slot:
- **Solid bar** — today's fill. Starts at 0 each day, climbs as tagged tasks
  and habits are completed. Max is the daily target.
- **Ghost bar** — the weekly compass score for that dimension, at 15–25%
  opacity. Gives context without competing.

When today's solid bar crosses the ghost, a brief shimmer and the ghost
nudges up slightly — the visual "you just lifted your compass" moment.

### Daily target (what "full" means on Home)

```
daily_target_points(dim) = max(1, round(weekly_target(dim) / 5))
```

Default weekly target is 10, so daily is 2 points — one medium task or two
small ones. Bars fill 0 → 100% as tasks complete; past the target, a small
"+" cap glows but the bar doesn't overflow visually.

Why 5 (not 7): most people don't want to feel behind on rest days. A user
who hits target Mon–Fri is already on pace for the full week.

---

## 3. Tying daily progress to the overall compass

A completed tagged task should feel like it's doing three things:

1. **Task list** → task strikes through (existing).
2. **Home bar** → particle flies to the matching bar; solid fill rises by
   `effort_points / dimensions_tagged`.
3. **Compass link** → the ghost bar behind nudges up by a fraction
   (`effort_points / 7` / `weekly_target`). Microcopy updates:
   *"Today +2 Body — nudging your compass up."*

The ghost doesn't need to be mathematically exact in the moment — what
matters is the *felt* connection: today's action moved the weekly number.
BalanceManager can still compute the true weekly composite lazily in the
background.

### Empty state

Day 0 (no tasks, no check-ins): bars show a slow breathing pulse at 15–25%
opacity (the ghost layer only). Copy: *"Today's fresh — tag a task and
watch it fill."* No "no data" sadness, just an invitation.

---

## 4. Implementation sketch

### New methods on `BalanceManager`

```swift
// Today-only signal (for Home)
func todayPoints(for dim: LifeDimension) -> Double
func dailyTarget(for dim: LifeDimension) -> Double
func todayFill(for dim: LifeDimension) -> Double  // 0.0 – 1.0+

// New display curve
func harmonyScoreFloored(for weekStart: Date? = nil) -> Int
func harmonyStage(for weekStart: Date? = nil) -> HarmonyStage
```

`HarmonyStage` is the 5-level enum (`.seedling`, `.rooting`, `.flowing`,
`.thriving`, `.radiant`) with color + label + next-step copy.

### Changes to BalanceScore math

```swift
func balanceScoreRaw(for weekStart: Date? = nil) -> Double {
    let scores = weeklyScores(for: weekStart)
    let values = LifeDimension.scored.map { scores[$0] ?? 0 }
    guard !values.isEmpty else { return 0 }

    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
    let stdev = sqrt(variance)
    let lowest = values.min() ?? 0
    let minWeight = min(1.0, lowest / 3.0)

    let raw = mean - 0.5 * stdev + 0.5 * minWeight
    return max(0, min(10, raw))
}

func harmonyScoreFloored(for weekStart: Date? = nil) -> Int {
    let raw = balanceScoreRaw(for: weekStart)
    let display = 30.0 + 70.0 * pow(raw / 10.0, 0.7)
    return Int(display.rounded())
}
```

### Changes to BalancePulseCard

The card is currently `scores: [LifeDimension: Double]` (weekly). Split the
input into two:

```swift
let todayFill: [LifeDimension: Double]     // 0.0 – 1.0+  (solid bar)
let weeklyScores: [LifeDimension: Double]  // 0.0 – 10.0  (ghost bar)
let harmonyScore: Int                       // new display
let stage: HarmonyStage
```

Render two rounded rects per slot: the ghost bar sized by
`weeklyScores[dim]/10`, the solid bar sized by `min(1, todayFill[dim])`.
Particle lands on the solid bar; both animate.

### Compass keeps its today strip

CompassView gets a slim "Today" row above the radar:

```
Today's contribution
  Body +2   Mind +1   Soul 0   Hustle +3
```

Small, muted, no decorations — just a reminder that the weekly radar is
built out of these daily deposits.

---

## 5. Copy tweaks (pruning the "low" language)

Nudges currently say things like *"Your Physical activity is low this
week."* Shift to growth framing:

| Today | Proposed |
|-------|----------|
| "Your Emotional is low." | "Emotional is ready for some love." |
| "Your Mental consistency is low. Try adding a daily activity." | "A small Mental moment each day would thrive." |
| "You've rated Spiritual satisfaction low." | "What would bring Spiritual back to life?" |
| "Balance streak broken." | *(remove)* — streaks are opt-in, and breaks aren't messaged. |

Rule of thumb: the app never tells the user they're *below* something. It
tells them where the next small step *leads*.

---

## 6. Open questions

- **Daily target of 2 points** — right default, or should it adapt from
  observed behavior (e.g. 70th percentile of user's own dim-days)?
- **Ghost bar exact value** — live weekly score, or yesterday's weekly
  score (so it doesn't shift under the user mid-day)? Yesterday is more
  stable; live is more truthful.
- **Sparkline on Compass cards** — 4 weeks is short; show 12 with zoom?
- **Stage labels** — Seedling / Rooting / Flowing / Thriving / Radiant
  have a growth-vs-plant metaphor. Alternate: Still / Stirring / Moving /
  Rising / Soaring (movement metaphor). Pick one family and commit.

---

## 7. Migration

- `harmonyScore` keeps its old callers working (just returns the new
  floored value). No caller does math on the result — it's only displayed —
  so flipping the implementation is safe.
- Balance streak threshold (currently `>= 3.0 raw`) can stay, since raw
  values themselves aren't changing much. Or raise to `4.0` to make the
  streak feel earned under the gentler penalty.
- `balanceSummaryForAI()` should send *both* the raw score (for the model
  to reason about) and the display score + stage (so AI messages match the
  user's UI).
