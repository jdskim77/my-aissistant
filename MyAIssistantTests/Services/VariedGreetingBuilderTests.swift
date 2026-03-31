import XCTest
@testable import MyAIssistant

final class VariedGreetingBuilderTests: XCTestCase {

    // MARK: - Basic Greeting

    func testGreetingNotEmpty() {
        let greeting = VariedGreetingBuilder.greeting(
            todayTaskCount: 3,
            completedTodayCount: 1,
            highPriorityTitles: [],
            completionRate: 33,
            streak: 0
        )
        XCTAssertFalse(greeting.isEmpty)
    }

    func testGreetingWithOpenerReturnsResult() {
        let result = VariedGreetingBuilder.greetingWithOpener(
            todayTaskCount: 3,
            completedTodayCount: 1,
            highPriorityTitles: [],
            completionRate: 33,
            streak: 0
        )
        XCTAssertFalse(result.opener.isEmpty)
        XCTAssertFalse(result.text.isEmpty)
        XCTAssertTrue(result.text.contains(result.opener))
    }

    // MARK: - Zero Tasks

    func testGreetingWithZeroTasks() {
        let greeting = VariedGreetingBuilder.greeting(
            todayTaskCount: 0,
            completedTodayCount: 0,
            highPriorityTitles: [],
            completionRate: 0,
            streak: 0
        )
        XCTAssertFalse(greeting.isEmpty)
        // Should contain some indication of clear schedule
    }

    // MARK: - All Tasks Done

    func testGreetingWithAllTasksDone() {
        let greeting = VariedGreetingBuilder.greeting(
            todayTaskCount: 5,
            completedTodayCount: 5,
            highPriorityTitles: [],
            completionRate: 100,
            streak: 3
        )
        XCTAssertFalse(greeting.isEmpty)
    }

    // MARK: - Partial Progress

    func testGreetingWithPartialProgress() {
        let greeting = VariedGreetingBuilder.greeting(
            todayTaskCount: 10,
            completedTodayCount: 3,
            highPriorityTitles: ["Submit report"],
            completionRate: 30,
            streak: 0
        )
        XCTAssertFalse(greeting.isEmpty)
    }

    // MARK: - High Priority Task

    func testGreetingMentionsHighPriorityTask() {
        // Run multiple times since it uses randomElement — at least one should mention the task
        var mentionedTask = false
        for _ in 0..<20 {
            let greeting = VariedGreetingBuilder.greeting(
                todayTaskCount: 3,
                completedTodayCount: 0,
                highPriorityTitles: ["Urgent deadline"],
                completionRate: 0,
                streak: 0
            )
            if greeting.contains("Urgent deadline") {
                mentionedTask = true
                break
            }
        }
        XCTAssertTrue(mentionedTask, "At least one greeting should mention the high priority task")
    }

    // MARK: - Streak Messages

    func testHighStreakIncludesStreakInfo() {
        // With streak >= 5, motivational snippet should mention the streak
        var mentionedStreak = false
        for _ in 0..<20 {
            let greeting = VariedGreetingBuilder.greeting(
                todayTaskCount: 1,
                completedTodayCount: 0,
                highPriorityTitles: [],
                completionRate: 50,
                streak: 7
            )
            if greeting.contains("7") {
                mentionedStreak = true
                break
            }
        }
        XCTAssertTrue(mentionedStreak, "High streak greeting should mention the streak count")
    }

    func testMediumStreakIncludesStreakInfo() {
        var mentionedStreak = false
        for _ in 0..<20 {
            let greeting = VariedGreetingBuilder.greeting(
                todayTaskCount: 1,
                completedTodayCount: 0,
                highPriorityTitles: [],
                completionRate: 50,
                streak: 3
            )
            if greeting.contains("3") {
                mentionedStreak = true
                break
            }
        }
        XCTAssertTrue(mentionedStreak, "Medium streak greeting should mention the streak count")
    }

    // MARK: - Exclude Openers

    func testExcludeOpenersReducesPool() {
        // Generating with a huge exclude set should still produce a greeting
        let allPossible = Set(["Good morning!", "Morning!", "Rise and shine!", "Top of the morning!",
                                "Good afternoon!", "Hey there!", "Good evening!", "Evening!",
                                "Hey, night owl!", "Still going strong!"])
        let result = VariedGreetingBuilder.greetingWithOpener(
            todayTaskCount: 1,
            completedTodayCount: 0,
            highPriorityTitles: [],
            completionRate: 0,
            streak: 0,
            excludeOpeners: allPossible
        )
        // Should still produce a result even if all known openers are excluded
        XCTAssertFalse(result.text.isEmpty)
    }

    // MARK: - Completion Rate Message

    func testHighCompletionRateMessage() {
        var mentionedRate = false
        for _ in 0..<20 {
            let greeting = VariedGreetingBuilder.greeting(
                todayTaskCount: 1,
                completedTodayCount: 0,
                highPriorityTitles: [],
                completionRate: 90,
                streak: 1  // Low streak so rate message triggers
            )
            if greeting.contains("90") {
                mentionedRate = true
                break
            }
        }
        XCTAssertTrue(mentionedRate, "High completion rate should be mentioned")
    }
}
