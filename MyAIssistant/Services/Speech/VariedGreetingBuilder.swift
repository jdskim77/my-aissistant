import Foundation

enum VariedGreetingBuilder {

    struct GreetingResult {
        /// The opener phrase (e.g. "Good morning!") — tracked for dedup.
        let opener: String
        /// The full assembled greeting text.
        let text: String
    }

    static func greetingWithOpener(
        todayTaskCount: Int,
        completedTodayCount: Int,
        highPriorityTitles: [String],
        completionRate: Int,
        streak: Int,
        excludeOpeners: Set<String> = []
    ) -> GreetingResult {
        let opener = timeOfDayGreeting(excluding: excludeOpeners)
        let parts = [
            opener,
            scheduleSnippet(
                todayTaskCount: todayTaskCount,
                completedTodayCount: completedTodayCount,
                highPriorityTitles: highPriorityTitles
            ),
            motivationalSnippet(streak: streak, completionRate: completionRate)
        ].filter { !$0.isEmpty }

        return GreetingResult(opener: opener, text: parts.joined(separator: " "))
    }

    /// Convenience that returns just the text (for callers that don't need the opener).
    static func greeting(
        todayTaskCount: Int,
        completedTodayCount: Int,
        highPriorityTitles: [String],
        completionRate: Int,
        streak: Int,
        excludeOpeners: Set<String> = []
    ) -> String {
        greetingWithOpener(
            todayTaskCount: todayTaskCount,
            completedTodayCount: completedTodayCount,
            highPriorityTitles: highPriorityTitles,
            completionRate: completionRate,
            streak: streak,
            excludeOpeners: excludeOpeners
        ).text
    }

    // MARK: - Time of Day (Large Variety)

    private static func timeOfDayGreeting(excluding used: Set<String>) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let options: [String]

        switch hour {
        case 5..<12:
            options = [
                "Good morning!",
                "Morning!",
                "Rise and shine!",
                "Top of the morning!",
                "Bright and early!",
                "Hope you slept well!",
                "Ready for a great day?",
                "New day, new possibilities!",
                "Let's make today count!",
                "Fresh start to the day!",
                "Hello and good morning!",
                "What a morning!",
                "Morning sunshine!",
                "Up and at 'em!",
                "Let's get this day started!",
                "Here we go, new day ahead!",
                "Wakey wakey!",
                "The day is yours!",
                "Another beautiful morning!",
                "Time to seize the day!"
            ]
        case 12..<17:
            options = [
                "Good afternoon!",
                "Hey there!",
                "Hope your day's going well!",
                "Afternoon check-in!",
                "How's the day treating you?",
                "Halfway through the day!",
                "Hope you're having a good one!",
                "Back at it!",
                "Let's keep the momentum going!",
                "Checking in this afternoon!",
                "Hey! How's everything going?",
                "Afternoon vibes!",
                "Hope lunch was good!",
                "Powering through the afternoon!",
                "The day's flying by!",
                "Still going strong this afternoon!",
                "Let's finish the day strong!",
                "What's on your mind this afternoon?",
                "Glad you're here!",
                "Ready for the rest of the day?"
            ]
        case 17..<21:
            options = [
                "Good evening!",
                "Evening!",
                "Winding down?",
                "How was your day?",
                "Evening check-in!",
                "Hope today was productive!",
                "Welcome to the evening!",
                "Time to relax a bit?",
                "How'd everything go today?",
                "The evening's here!",
                "Nice to see you this evening!",
                "Wrapping up the day?",
                "Let's review how today went!",
                "Almost done for the day!",
                "Evening vibes!",
                "Hope you had a great day!",
                "Taking a breather?",
                "Ready to wind down?",
                "The hard part's over!",
                "Let's close out the day!"
            ]
        default:
            options = [
                "Hey, night owl!",
                "Still going strong!",
                "Burning the midnight oil?",
                "Late night check-in!",
                "Can't sleep?",
                "Working late tonight?",
                "The night is young!",
                "Hope you're not too tired!",
                "Quiet hours, good thinking time!",
                "Late night productivity!",
                "Hey there, up late?",
                "Nothing like a late-night session!",
                "Midnight motivation!",
                "The world is asleep but you're crushing it!",
                "Night shift mode!",
                "Still at it?",
                "Burning through the night!",
                "A little late night planning?",
                "Rest when you're done!",
                "Making the most of the quiet hours!"
            ]
        }

        // Prefer unused greetings; fall back to any if all have been used
        let unused = options.filter { !used.contains($0) }
        return (unused.isEmpty ? options : unused).randomElement()!
    }

    // MARK: - Schedule Snippet (Varied)

    private static func scheduleSnippet(
        todayTaskCount: Int,
        completedTodayCount: Int,
        highPriorityTitles: [String]
    ) -> String {
        let remaining = todayTaskCount - completedTodayCount

        if todayTaskCount == 0 {
            return [
                "Your schedule is clear today.",
                "Nothing on the agenda today — enjoy the freedom!",
                "No tasks today, it's all yours!",
                "A blank slate today!",
                "Clear schedule — what would you like to do?"
            ].randomElement()!
        }

        if remaining == 0 {
            return [
                "You crushed all \(todayTaskCount) tasks today!",
                "All \(todayTaskCount) tasks done — nice work!",
                "Everything's checked off — \(todayTaskCount) for \(todayTaskCount)!",
                "You finished everything on your list today!",
                "All done! \(todayTaskCount) tasks completed."
            ].randomElement()!
        }

        var snippet: String
        if completedTodayCount > 0 {
            snippet = [
                "You've knocked out \(completedTodayCount) of \(todayTaskCount) tasks.",
                "\(completedTodayCount)/\(todayTaskCount) done so far — solid progress.",
                "\(completedTodayCount) down, \(remaining) to go!",
                "Making progress — \(completedTodayCount) of \(todayTaskCount) done.",
                "Nice momentum — \(completedTodayCount) tasks completed so far."
            ].randomElement()!
        } else {
            snippet = [
                "You have \(todayTaskCount) tasks lined up today.",
                "\(todayTaskCount) tasks on your plate today.",
                "\(todayTaskCount) things to tackle today!",
                "Today's lineup: \(todayTaskCount) tasks.",
                "You've got \(todayTaskCount) tasks ahead of you."
            ].randomElement()!
        }

        if let top = highPriorityTitles.first {
            snippet += [
                " Top priority: \(top).",
                " First up: \(top).",
                " Most important: \(top).",
                " Focus on: \(top)."
            ].randomElement()!
        }

        return snippet
    }

    // MARK: - Motivational Snippet (Varied)

    private static func motivationalSnippet(streak: Int, completionRate: Int) -> String {
        if streak >= 5 {
            return [
                "\(streak)-day streak — you're on fire!",
                "That's \(streak) days in a row. Incredible!",
                "\(streak) days straight — unstoppable!",
                "Wow, \(streak)-day streak! Keep it rolling!"
            ].randomElement()!
        } else if streak >= 3 {
            return [
                "\(streak)-day streak, keep it going!",
                "Nice \(streak)-day streak!",
                "\(streak) days in a row — building a habit!",
                "On a \(streak)-day roll!"
            ].randomElement()!
        } else if completionRate >= 80 {
            return [
                "\(completionRate)% completion rate — impressive.",
                "Running at \(completionRate)% — strong work!",
                "\(completionRate)% completion — you're nailing it."
            ].randomElement()!
        }
        return ""
    }
}
