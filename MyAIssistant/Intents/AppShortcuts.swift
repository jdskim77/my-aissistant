import AppIntents

struct MyAIssistantShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodayScheduleIntent(),
            phrases: [
                "What's on my schedule in \(.applicationName)",
                "Show today's tasks in \(.applicationName)",
                "What do I have today in \(.applicationName)"
            ],
            shortTitle: "Today's Schedule",
            systemImageName: "calendar"
        )

        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task in \(.applicationName)",
                "Create a task in \(.applicationName)",
                "New task in \(.applicationName)"
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )

        AppShortcut(
            intent: MyStatsIntent(),
            phrases: [
                "How's my streak in \(.applicationName)",
                "Show my stats in \(.applicationName)",
                "Check my progress in \(.applicationName)"
            ],
            shortTitle: "My Stats",
            systemImageName: "chart.bar"
        )

        AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: [
                "Complete a task in \(.applicationName)",
                "Mark task done in \(.applicationName)",
                "Finish a task in \(.applicationName)"
            ],
            shortTitle: "Complete Task",
            systemImageName: "checkmark.circle"
        )

        AppShortcut(
            intent: ToggleHabitIntent(),
            phrases: [
                "Log a habit in \(.applicationName)",
                "Mark habit done in \(.applicationName)",
                "Track a habit in \(.applicationName)"
            ],
            shortTitle: "Log Habit",
            systemImageName: "leaf"
        )

        AppShortcut(
            intent: StartFocusIntent(),
            phrases: [
                "Start a focus session in \(.applicationName)",
                "Start the timer in \(.applicationName)",
                "Focus mode in \(.applicationName)"
            ],
            shortTitle: "Focus Session",
            systemImageName: "timer"
        )
    }
}
