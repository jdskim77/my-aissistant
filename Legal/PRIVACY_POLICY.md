# Privacy Policy

**Effective date:** April 8, 2026
**Last updated:** April 8, 2026

This Privacy Policy explains how Thrivn ("Thrivn", "we", "us", or "our") collects, uses, and protects your information when you use the Thrivn mobile application (the "App"). Thrivn is a personal assistant app that helps you plan your day, track check-ins and habits, and chat with an AI assistant.

We built Thrivn with privacy as a default. Almost everything you create lives on your device. We collect the minimum information needed to make the App work.

---

## 1. Who we are

Thrivn is operated by the developer of the Thrivn app. If you have any questions about this Privacy Policy or your data, you can reach us at:

**Email:** support@thrivn.app

(If a different contact email applies to your deployment, replace this address before publishing.)

---

## 2. Information we collect

### 2.1 Information you provide

- **Account information.** When you sign in with Apple, Apple shares a stable, anonymous user identifier with us. Depending on your Apple privacy choices, you may also share a name and an email address (which may be a private relay address). We never see your Apple ID password.
- **Content you create.** Tasks, check-ins, habits, focus sessions, journal notes, goals, and chat messages you create in the App. This content lives on your device and, if you have iCloud enabled for the App, in your private iCloud database.
- **Voice input you choose to use.** If you use voice input in chat, your speech is transcribed on-device using Apple's Speech Recognition framework. We do not record or store audio.
- **Calendar events you choose to import.** If you grant calendar access, the App reads events from your iOS calendars to display alongside your tasks. Calendar events are not sent to our servers.

### 2.2 Information collected automatically

- **Device and crash diagnostics.** We use Sentry to collect anonymized crash reports and error diagnostics so we can fix bugs. These reports include device model, OS version, app version, and a stack trace. They do not include the content of your tasks, messages, or check-ins. We do not send personally identifying information (PII) to Sentry.
- **Usage of the AI assistant.** When you send a message to the AI assistant, your message and a short context summary (e.g. recent tasks, today's check-in) are sent to our backend (see Section 3) and forwarded to our AI provider for a response. We log per-request metadata such as token counts and timestamps for billing and abuse prevention. We do not retain the content of your messages on our servers beyond the duration of the request.

### 2.3 Information we do **not** collect

- We do not use third-party analytics SDKs (no Google Analytics, no Facebook SDK, no AppsFlyer, no Branch).
- We do not track you across other apps or websites.
- We do not collect your location.
- We do not collect your contacts, photos, or browsing history.
- We do not sell your data. Ever.

---

## 3. How we use your information

| Purpose | What we use |
|---|---|
| Authenticate you so we can sync your data across your devices | Your Sign in with Apple identifier |
| Power the AI assistant chat feature | Your message + a short context summary, sent to our backend and our AI provider |
| Sync your tasks, check-ins, and habits across your devices | Your private iCloud database (Apple's CloudKit) |
| Show you reminders and notifications you opted into | Local notifications scheduled on your device |
| Diagnose and fix crashes | Anonymized crash reports via Sentry |
| Enforce fair-use limits and prevent abuse | Per-account request counts on our backend |
| Communicate with you about the service | The email Apple shared with us at sign-in (only if you wrote to us first) |

We rely on the following legal bases under GDPR for users in the European Economic Area: (a) **performance of a contract** to provide the App's core features, (b) **legitimate interests** to keep the service secure and to fix bugs, and (c) **consent** for any optional features you enable (such as calendar access or notifications).

---

## 4. Where your data lives

| Data | Where it lives | Who can read it |
|---|---|---|
| Tasks, check-ins, habits, goals, journal entries | On your device (encrypted with iOS Data Protection) and in your private iCloud database if iCloud is enabled | You (and Apple, under Apple's iCloud terms) |
| Anthropic / API keys, session tokens | iOS Keychain on your device | You only — never sent to our servers |
| AI chat messages (in transit) | Sent over HTTPS to our Cloudflare Workers backend, then to our AI provider | We see them only for the duration of the request; the AI provider processes them per their own privacy policy (see Section 5) |
| Crash diagnostics | Sentry (US-hosted) | Us, in aggregated form |
| Account identifier (Apple sub) | Our Cloudflare D1 database | Us |
| Per-request usage logs | Our Cloudflare D1 database | Us |

We use Cloudflare Workers, D1, and KV (operated by Cloudflare, Inc.) as our backend infrastructure. Cloudflare's privacy commitments are described at https://www.cloudflare.com/privacypolicy/.

---

## 5. Third-party services

We rely on a small number of third-party services to operate Thrivn. Each is listed here so you know exactly who touches your data.

| Provider | Purpose | What they receive | Their privacy policy |
|---|---|---|---|
| **Apple, Inc.** | Sign in with Apple, iCloud sync, Speech Recognition, Push Notifications | Account identifier, your iCloud data (in your private database) | https://www.apple.com/legal/privacy/ |
| **Anthropic, PBC** | AI model that generates assistant responses | Your chat message and a short context summary at the moment of your request | https://www.anthropic.com/legal/privacy |
| **Cloudflare, Inc.** | Backend hosting (Workers, D1, KV) | Routing your requests and storing per-account usage records | https://www.cloudflare.com/privacypolicy/ |
| **Sentry (Functional Software, Inc.)** | Crash reporting and error diagnostics | Anonymized crash reports with no message content or PII | https://sentry.io/privacy/ |

We do not share your data with any provider not listed above. We do not use any data broker, advertiser, or marketing partner.

---

## 6. AI assistant: what is sent and what is not

When you send a message to the in-app AI assistant, the following is sent to our backend and forwarded to Anthropic's API:

- The text of your message.
- A short context block summarizing recent activity (for example: a list of today's tasks, your most recent check-in, your active goal). This is generated by the App at the moment of your message.
- Conversation history within the current chat session, so the assistant can reply coherently.

The following is **not** sent:

- Your name, email, or Apple ID.
- Audio recordings (voice input is transcribed locally before sending).
- Calendar events from other apps unless they are in the context summary you can see in the chat preview.
- Any other tasks, check-ins, or notes that are not part of the current context.

Anthropic processes the request to generate a reply, then deletes it according to its own retention policy. We do not use your chat content to train any AI model.

---

## 7. Data retention

- **Content on your device and in iCloud:** retained until you delete it. Deleting your account also deletes this data on devices where you are signed in.
- **Account record on our backend:** retained for as long as your account is active. When you delete your account, we erase your account record and any per-request usage logs tied to it within 30 days.
- **Crash reports:** retained by Sentry for up to 90 days, then deleted automatically.
- **Backups and logs:** any operational logs that incidentally reference your account identifier are deleted within 30 days.

---

## 8. Your rights

You have the right to:

- **Access** the data we hold about you. Most of it lives on your device — open the App and you can see all of it.
- **Export** your data. Settings → Privacy → Export My Data produces a JSON file you can save anywhere.
- **Correct** any data you create — edit it directly in the App.
- **Delete** your account and all associated data. Settings → Account → Delete Account performs an immediate, irreversible deletion of your account on our backend and all locally stored data on the device. Data on other devices is removed the next time those devices launch the App.
- **Withdraw consent** for any optional permission (calendar, notifications, microphone) at any time in iOS Settings → Thrivn.
- **Object to processing** or **restrict processing** under GDPR. Contact us at the email above.
- **Lodge a complaint** with your local data protection authority.

We do not discriminate against users who exercise any of these rights.

---

## 9. Children's privacy

Thrivn is not directed to children under 13 (or under 16 in jurisdictions where that is the applicable age of digital consent). We do not knowingly collect personal information from children. If you believe a child has provided us with personal information, please contact us at the email above and we will delete it.

---

## 10. Security

We protect your information with industry-standard safeguards:

- All network requests use TLS 1.2 or higher.
- Sensitive credentials (API keys, session tokens) are stored in the iOS Keychain, never in plain files or `UserDefaults`.
- Local data is protected by iOS Data Protection (file encryption tied to your device passcode).
- Our backend authenticates every request and enforces per-account rate limits.
- We follow the principle of least privilege: every component only has access to the data it strictly needs.

No system is perfectly secure. If we ever discover a breach affecting your data, we will notify you within 72 hours of becoming aware of it, as required by applicable law.

---

## 11. International transfers

Our backend infrastructure is operated by Cloudflare, which routes requests to data centers around the world for performance and reliability. Anthropic processes AI requests on infrastructure it operates in the United States. By using the App, you consent to your data being processed in jurisdictions outside your country of residence, with the safeguards described above.

---

## 12. Changes to this policy

We may update this Privacy Policy from time to time. If we make a material change, we will notify you in the App and update the "Last updated" date at the top. Your continued use of the App after a change becomes effective constitutes acceptance of the updated policy.

---

## 13. Contact

If you have any questions, concerns, or requests about your privacy, please contact us at:

**support@thrivn.app**

We aim to respond within 7 days.
