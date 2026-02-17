# Personal Assistant App - Prototype Specifications

## Overview
Build an interactive iOS app prototype (SwiftUI) for a personal assistant and scheduling tool that learns user patterns, sends daily check-ins, and helps manage tasks with AI assistance.

## Core Features

### 1. Daily Check-ins (4x per day)
- **Morning Brief** (8:00 AM): Motivational summary, today's tasks, streak update
- **Midday Check-in** (1:00 PM): Progress update, remaining tasks
- **Late Afternoon** (6:00 PM): Day wrap-up, tomorrow's preview
- **Night Wind-down** (10:00 PM): Completion summary, high-priority upcoming tasks

Each check-in has:
- Custom icon (🌅 ☀️ 🌆 🌙)
- Unique color scheme
- Contextual messaging (motivational & encouraging tone)
- Task focus appropriate to time of day

### 2. Schedule Management
- Timeline view grouped by date
- Task categories: Travel, Errand, Personal
- Priority levels: High (coral/red), Medium (gold), Low (gray)
- Each task includes:
  - Title
  - Icon (emoji)
  - Due date
  - Category
  - Priority
  - Optional notes
  - Done/not done status

### 3. Pattern Tracking
Track and display:
- Current streak (consecutive days active)
- Completion rate (%)
- Average tasks per day
- Best check-in time
- Weekly task completion bar chart
- Check-in consistency heatmap (last 7 days)
- Category breakdown with progress bars

### 4. AI Assistant
- Chat interface with Claude Sonnet 4
- Context-aware: knows full schedule, patterns, and stats
- Motivational and encouraging tone
- Quick action chips for common queries
- Real-time streaming responses

### 5. Home Dashboard
Displays at a glance:
- Time-appropriate greeting
- Current date
- Next check-in time with preview
- Stats cards: days until next major event, today's tasks, completed count
- Major event countdown (e.g., trip) with progress bar
- Current streak with 7-day visual indicator
- Top 3 high-priority upcoming tasks

## Design System

### Color Palette (Warm, Natural Theme)
```
Background: #F8F5F0 (warm cream)
Surface: #FFFFFF
Card: #FFFEFB
Border: #E8E2D9
Accent (primary): #2D5016 (deep green)
Accent warm: #4A7C2F
Accent light: #E8F0E0
Gold: #B8860B
Coral (high priority): #C94B2B
Sky blue: #1A5276
Text primary: #1A1A14
Text secondary: #6B6555
Text muted: #A8A090

Check-in colors:
Morning: #FF9500 (orange)
Noon: #34C759 (green)
Afternoon: #007AFF (blue)
Night: #5856D6 (purple)
```

### Typography
- Display font: "Cormorant Garamond" (headings, numbers)
- Body font: "Outfit" (all other text)

### UI Patterns
- iPhone shell: 393x852px with notch
- Border radius: 12-20px for cards
- Smooth animations: fadeUp (0.3-0.6s)
- Hover states on interactive elements
- Priority badges with colored backgrounds
- Progress bars with smooth transitions

## Data Structure

### Task/Event Object
```swift
struct Event {
    let id: String
    var title: String
    var category: String // "Travel", "Errand", "Personal"
    var priority: String // "high", "medium", "low"
    var date: Date
    var done: Bool
    var icon: String // emoji
    var notes: String
}
```

### Pattern Data
```swift
struct PatternData {
    var streak: Int
    var completionRate: Int // percentage
    var avgTasksPerDay: Double
    var weeklyDone: [Int] // array of 7 integers (Mon-Sun)
    var checkinHistory: [Bool] // last 7 days
}
```

## Screens & Navigation

### Bottom Navigation (5 tabs)
1. **Home** (⌂) - Dashboard overview
2. **Schedule** (📅) - Full timeline, add tasks (shows badge for pending today)
3. **Check-ins** (🔔) - Daily briefs selector
4. **Patterns** (📊) - Analytics & insights
5. **Assistant** (✦) - AI chat

### Screen Details

#### Home Screen
- Greeting header with date
- Next check-in card (tappable → opens Check-ins screen)
- 3 stat cards in grid
- Major event countdown banner
- Streak card with 7-day indicator
- High priority upcoming section (3 tasks max)

#### Schedule Screen
- Header with month title + "Add" button
- Category filter pills (All, Travel, Errand, Personal)
- Collapsible "Add task" form with:
  - Icon picker grid
  - Text input
  - Date selector
  - Category selector
  - Priority buttons
- Timeline grouped by date with:
  - Date badge (pulsing animation for "Today")
  - Task count summary
  - Task cards with checkbox, icon, title, notes, priority badge

#### Check-ins Screen
- Horizontal selector for 4 check-in times
- Active check-in displays:
  - Summary card with time-specific message
  - Motivation tip card
  - Relevant task list (focus tasks / completed / upcoming)
  - "Open Full Schedule" CTA button

#### Patterns Screen
- 4 key metric cards in 2x2 grid
- Weekly bar chart with days labeled
- Check-in consistency grid (7 boxes)
- Category breakdown with progress bars

#### Chat Screen
- Header with AI avatar (animated pulse)
- Message bubbles (user: right/green, assistant: left/white)
- Quick action chips (4 suggestions)
- Input textarea with send button

## Seeded Data Example (February 2026)

Current date: Feb 10, 2026
Major event: Dubai trip Feb 15-20

Sample tasks:
- Feb 10: Book airport transfer (Travel, High)
- Feb 10: Pick up travel insurance (Errand, High)
- Feb 11: Exchange currency (Errand, High)
- Feb 13: Pack luggage (Travel, High)
- Feb 15: Depart for Dubai (Travel, High)
- Feb 17: Desert safari (Travel, Medium)
- Feb 20: Return flight (Travel, High)
- Feb 21: Grocery run (Errand, Medium)
- Feb 25: Pay bills (Errand, High)
- Feb 27: Car service (Errand, Medium)

Already completed:
- Feb 3: Book flights (Travel, High) ✓
- Feb 5: Renew passport (Errand, High) ✓
- Feb 6: Book hotel (Travel, High) ✓

Pattern stats:
- Streak: 6 days
- Completion rate: 78%
- Avg tasks/day: 2.3
- Weekly done: [2, 3, 1, 4, 3, 2, 0]
- Check-in history: [✓, ✓, ✗, ✓, ✓, ✓, ✓]

## AI Integration

### Claude API Setup
- Model: claude-sonnet-4-20250514
- Max tokens: 1000
- System prompt template:
  ```
  You are a warm, motivational personal assistant. The user has a Dubai trip on Feb 15-20, 2026. 
  Today is [current_date]. Their stats: [completion_rate]% completion, [streak]-day streak. 
  
  Schedule:
  [task_list_with_status]
  
  Be encouraging, concise, proactive. Celebrate wins. Surface urgent items. 
  Use emojis sparingly. No markdown headers or bullets.
  ```

### Suggested Quick Actions
- "Am I ready for Dubai?"
- "What's high priority this week?"
- "Give me a pep talk"
- "What's due this week?"

## Animations & Interactions

### Key Animations
- fadeUp: entrance animation (0.3-0.65s stagger)
- pulse: loading dots (1.2s infinite)
- glow: "Today" badge (2s infinite)
- Button press: scale(0.97) on active
- Row hover: background color transition

### Interactive Elements
- All cards and buttons: subtle press animation
- Task checkboxes: toggle with animation
- Priority filters: active state with color fill
- Timeline dates: pulsing for current day
- AI chat: typing indicator with animated dots

## Technical Requirements

### For Prototype
- SwiftUI for iOS 17+
- Anthropic API integration (fetch to https://api.anthropic.com/v1/messages)
- Date handling with Foundation
- Local state management (no persistence needed for prototype)
- Responsive to iPhone 15 Pro dimensions (393x852)

### Optional Future Enhancements (Not for Prototype)
- WhatsApp notifications via Twilio
- Google Calendar sync
- Google Sheets logging
- Persistent storage
- Push notifications
- Multi-language support

## User Experience Principles

1. **Motivational & Encouraging**: All copy should be warm, supportive, celebrating progress
2. **Pattern Recognition**: Surface insights about user behavior naturally
3. **Contextual Intelligence**: Check-ins adapt to time of day and current schedule
4. **Minimal Friction**: Quick actions, one-tap completions, smart defaults
5. **Visual Clarity**: Clear hierarchy, readable typography, generous spacing
6. **Delightful Details**: Smooth animations, emoji icons, progress indicators

## Implementation Priority

### Phase 1 (Prototype - Build This First)
✓ All 5 screens with navigation
✓ Seeded February data
✓ Task completion toggle
✓ Add task form
✓ AI chat with Claude
✓ Pattern visualization
✓ Check-in briefs
✓ Responsive design

### Phase 2 (Future - Not Now)
- Persistent data storage
- Custom date ranges
- Export/share features
- Notification system
- WhatsApp integration
- Calendar sync

---

## Getting Started

1. Create new SwiftUI iOS app project
2. Add Anthropic API integration
3. Build data models (Event, PatternData)
4. Create bottom tab navigation
5. Implement each screen view
6. Seed with February 2026 data
7. Connect AI chat functionality
8. Add animations and polish

This is a high-fidelity prototype meant to validate UX flows and visual design before building production features.
