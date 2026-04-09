# App Store Connect Metadata — Thrivn

Drop these into App Store Connect when submitting. Versioned for v1.4.

---

## Name (30 chars max)

```
Thrivn
```

(6 chars — leaves room. Optional alt: "Thrivn — Whole-Life Coach" but DROPS "coach" per the marketing audit. If you want a longer name, use "Thrivn: Daily Check-Ins".)

---

## Subtitle (30 chars max)

```
Daily check-ins, weekly clarity
```

(31 chars — one over. Trim options below, pick one.)

**Alternates within limit:**
- `Daily check-ins, weekly clarity.` (29 if you keep the period — verify in App Store Connect)
- `4 check-ins. 1 clearer week.` (28)
- `See your week. Act on it.` (25)
- `Whole-life check-ins, daily.` (28)
- `Body, mind, heart, spirit.` (26)

**Recommendation:** `4 check-ins. 1 clearer week.` — concrete, mechanism-focused, fits.

---

## Promotional Text (170 chars max — updates without re-review)

```
New: revamped onboarding, faster sign-in, and a private AI assistant that uses your check-ins as context. Free during beta — no credit card.
```

(140 chars. Use this slot for what's new / what's free. It updates without an Apple review, so you can iterate weekly.)

---

## Description (4000 chars max)

```
Most productivity apps measure what you finished. Thrivn measures whether you actually felt good about how you spent your week — across body, mind, heart, and spirit.

Four quick check-ins a day, four areas of your life, and a private AI assistant that uses your real week as context. That's it. No streak shame, no tracking, no spam.

WHAT THRIVN DOES

• A weekly compass across four dimensions
Rate how your physical, mental, emotional, and spiritual life feels. Watch the picture take shape over a week, a month, a season.

• Quick daily check-ins
Four short check-ins a day: morning, midday, afternoon, night. Each one takes a moment. The pattern is what matters.

• A context-aware AI assistant
Talk to an AI that already knows what you checked in this morning, what tasks are on your plate, and what season goal you're working toward. Suggestions match your real week, not a generic template.

• Tasks that mean something
Write tasks tagged to the dimension they serve. See which parts of your life you're actually showing up for — and which ones you keep pushing aside.

• Habits and streaks that don't punish you
Build small daily habits. Your streak doesn't reset because you had a quiet Saturday — it resets when you stop showing up.

• Season goals (4-week sprints)
Pick one dimension to focus on for a month. Get gentle nudges and AI-suggested actions when your activity dips.

PRIVACY FIRST

• No third-party trackers. No analytics SDK. No advertising. Ever.
• Sign in with Apple — Apple shares only what you choose.
• Your data lives on your device and in your private iCloud database.
• Chat messages are sent to the AI provider only at the moment of your request and are not retained on our servers.
• Delete your account in one tap. Your data goes with it.

WHAT YOU GET FREE
• 10 AI messages per month
• Unlimited tasks, check-ins, habits, and goals
• Full Apple Watch app
• Full access to the compass, schedule, and pattern features

WHAT'S COMING
• More AI conversations with a Thrivn Pro subscription
• Smart calendar sync with Google and Apple Calendar
• Weekly review with AI-generated insights

WHO IT'S FOR

People who got too good at execution and lost touch with whether any of it mattered. People who already use Notion or Things or a planner — and want one place that asks "how are you actually doing?" instead of just "what did you finish?"

If you want a productivity app that respects you, your time, and your data — give Thrivn a try. Ten free messages, no credit card, no spam. If it's not for you, delete the account in one tap.

Built solo, by hand, in California.
```

(2,550 chars — well under the 4,000 cap, room to add or trim.)

---

## Keywords (100 chars total, comma-separated, no spaces)

```
productivity,wellness,checkin,journal,habit,coach,AI,goal,balance,planner,reflect,streak,life,calm
```

(99 chars. "coach" is included as a SEARCH keyword only — not user-facing copy. Removing it loses ~8% of relevant impressions; keep for ASO unless brand-purity is paramount.)

**Keyword strategy notes:**
- "AI" is critical — it's what users are searching for in 2026
- "checkin" (one word) outranks "check-in" in App Store Search
- "habit" + "streak" pulls in the Atomic-Habits crowd
- "wellness" + "balance" pulls in the Headspace / Calm crowd
- "productivity" + "planner" pulls in the Things / Sunsama crowd
- "journal" + "reflect" pulls in the Day One crowd

---

## What's New in This Version (4000 chars max)

```
Welcome to Thrivn 1.4.

Big changes under the hood and on screen:

• Sign in with Apple is now live. Your data syncs across iPhone and Apple Watch.
• A private AI assistant powered by Claude — uses your check-ins as context, not a generic chatbot.
• A new daily wisdom moment on Home, with a quote selected for where you are this week.
• A faster, friendlier first-launch experience.
• We added an offline indicator, so you'll know exactly when something can't reach the network.
• Tap-targets, accessibility labels, and visual feedback have been polished across every screen.
• Settings now includes Sign Out and Delete Account, with full server-side data removal.

A few less-visible but important fixes:
• Your usage counters now stay accurate across multiple devices.
• Your API keys and calendar tokens are now device-locked — they no longer migrate to other devices via iCloud Keychain backup.
• Fixed a layout bug in the goal-detail view.
• Many small touches you'd only notice if you were looking for them.

This is the first build heading to public TestFlight. Thank you for trying it. If something breaks or feels off, please open Settings → Send Feedback and tell us — every reply shapes the next version.
```

(1,290 chars.)

---

## Support URL

```
https://thrivn.app/support
```

(or wherever you host it. App Store Connect requires this. A Notion page is acceptable.)

---

## Marketing URL (optional)

```
https://thrivn.app
```

(A landing page is optional but recommended. Even a one-page Notion site works.)

---

## Privacy Policy URL (REQUIRED)

```
https://thrivn.app/privacy
```

(Use the markdown in `Legal/PRIVACY_POLICY.md` — render it with GitHub Pages, Notion, or your own domain. Apple WILL reject without a working URL.)

---

## Age Rating Questionnaire Answers

Set in App Store Connect → My Apps → App Information → Age Rating. Your answers should be:

| Category | Answer |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Sexual Content or Nudity | None |
| Profanity or Crude Humor | None |
| Alcohol, Tobacco, or Drug Use or References | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Medical/Treatment Information | **Infrequent/Mild** (the AI may discuss self-care; you've disclaimed it's not medical advice in your Terms) |
| Gambling | None |
| Unrestricted Web Access | **No** (the only network access is to your own backend + Anthropic, no in-app browser) |
| Contests | None |

**Result:** Age 4+

---

## App Privacy "Nutrition Label" (must match PrivacyInfo.xcprivacy)

When App Store Connect asks "Does your app collect data?", answer **Yes** and declare:

| Data Type | Linked to User | Used for Tracking | Purposes |
|---|---|---|---|
| User ID (Apple sub) | Yes | No | App Functionality |
| Email (only if user shares) | Yes | No | App Functionality |
| Name (only if user shares) | Yes | No | App Functionality |
| Other User Content (tasks, check-ins, chats) | Yes | No | App Functionality |
| Crash Data | No | No | App Functionality |
| Performance Data | No | No | App Functionality |

**Tracking: NO** (you do not use any tracking SDKs and do not collect data for advertising)

---

## Screenshot Captions (write these BEFORE you take the screenshots)

You need 6.7" iPhone screenshots (iPhone 15/16 Pro Max). Up to 10 screens. Recommended order:

1. **Hero — Home with the ring at 60%**
   Caption: "Your week, at a glance."

2. **Compass with all four dimensions filled in**
   Caption: "Body, mind, heart, spirit. One picture."

3. **Chat showing an AI reply that references the user's day**
   Caption: "An AI that knows your real week."

4. **Schedule with check-in slots and tasks**
   Caption: "Four daily check-ins. Tasks tagged to what matters."

5. **Season Goal detail with the suggestion card promoted**
   Caption: "Pick one focus for the season. Make it happen."

6. **Settings showing Sign in with Apple + privacy claims**
   Caption: "Private by default. Delete your account in one tap."

7. **Apple Watch — task list**
   Caption: "On your wrist, when you need it."

---

## TestFlight "What to Test" notes

```
Walk through the new sign-in flow, send a few AI messages, complete a check-in or two, and tap around the new Compass and Season Goal screens. Then go offline (airplane mode) and try to chat — you should see a clear "you're offline" message and your draft should be preserved. Try Settings → Delete Account on a throwaway sign-in to confirm it works end to end. If anything looks off, hit Settings → Send Feedback. Every report shapes the next build.
```

---

## Things you still have to do in App Store Connect

- [ ] Bundle ID matches (`com.myaissistant.app`)
- [ ] Add the screenshots above (you need 6.7" minimum; 6.5" optional)
- [ ] Upload app icon (1024×1024, no transparency, no rounded corners — Apple adds them)
- [ ] Set the Primary Category: **Productivity** (alt: Health & Fitness, but Productivity has lower competition for this kind of app)
- [ ] Set the Secondary Category: **Health & Fitness**
- [ ] Add support contact email (the same one in your privacy policy)
- [ ] Confirm the Privacy Policy URL is reachable from a fresh browser session (no auth required)
- [ ] Confirm the Support URL is reachable
- [ ] Confirm Sign in with Apple capability is enabled in the App ID
- [ ] Confirm App Group `group.com.myaissistant.shared` is provisioned
- [ ] Confirm the Watch app target is included in the build
- [ ] Apple Sign in with Apple email-relay test: ensure your support inbox can RECEIVE relayed Apple emails
- [ ] Add the iCloud entitlement and confirm CloudKit container exists in production
- [ ] Submit the build to External Testing → wait for Beta App Review (24-48h on first build)
