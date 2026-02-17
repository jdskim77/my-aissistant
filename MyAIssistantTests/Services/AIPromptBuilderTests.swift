import XCTest
@testable import MyAIssistant

final class AIPromptBuilderTests: XCTestCase {

    // MARK: - Chat System Prompt

    func testChatSystemPromptContainsSchedule() {
        let prompt = AIPromptBuilder.chatSystemPrompt(
            scheduleSummary: "○ Feb 16: Team meeting [High] (Work)",
            completionRate: 75,
            streak: 3
        )

        XCTAssertTrue(prompt.contains("Team meeting"))
        XCTAssertTrue(prompt.contains("75%"))
        XCTAssertTrue(prompt.contains("3-day streak"))
    }

    func testChatSystemPromptEmptySchedule() {
        let prompt = AIPromptBuilder.chatSystemPrompt(
            scheduleSummary: "",
            completionRate: 0,
            streak: 0
        )

        XCTAssertTrue(prompt.contains("No tasks yet."))
    }

    func testChatSystemPromptContainsDate() {
        let prompt = AIPromptBuilder.chatSystemPrompt(
            scheduleSummary: "test",
            completionRate: 50,
            streak: 1
        )

        // Should contain today's formatted date
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        let year = formatter.string(from: Date())
        XCTAssertTrue(prompt.contains(year))
    }

    // MARK: - Check-in Prompt

    func testCheckInPromptContainsTimeSlot() {
        let prompt = AIPromptBuilder.checkInPrompt(
            timeSlot: "Morning",
            scheduleSummary: "Tasks here",
            completionRate: 60,
            streak: 2,
            mood: nil
        )

        XCTAssertTrue(prompt.contains("Morning"))
        XCTAssertTrue(prompt.contains("60%"))
        XCTAssertTrue(prompt.contains("2-day streak"))
    }

    func testCheckInPromptWithMood() {
        let prompt = AIPromptBuilder.checkInPrompt(
            timeSlot: "Afternoon",
            scheduleSummary: "",
            completionRate: 80,
            streak: 5,
            mood: 4
        )

        XCTAssertTrue(prompt.contains("4/5"))
    }

    func testCheckInPromptWithoutMood() {
        let prompt = AIPromptBuilder.checkInPrompt(
            timeSlot: "Night",
            scheduleSummary: "",
            completionRate: 80,
            streak: 5,
            mood: nil
        )

        XCTAssertFalse(prompt.contains("/5"))
    }

    // MARK: - Weekly Review Prompt

    func testWeeklyReviewPromptContainsStats() {
        let prompt = AIPromptBuilder.weeklyReviewPrompt(
            weekSummary: "Task 1 (done)\nTask 2 (pending)",
            averageMood: 3.8,
            totalTasks: 10,
            completedTasks: 7,
            streak: 4
        )

        XCTAssertTrue(prompt.contains("7/10"))
        XCTAssertTrue(prompt.contains("4 days"))
        XCTAssertTrue(prompt.contains("3.8"))
        XCTAssertTrue(prompt.contains("Task 1"))
    }

    func testWeeklyReviewPromptWithoutMood() {
        let prompt = AIPromptBuilder.weeklyReviewPrompt(
            weekSummary: "",
            averageMood: nil,
            totalTasks: 0,
            completedTasks: 0,
            streak: 0
        )

        XCTAssertFalse(prompt.contains("Average mood"))
        XCTAssertTrue(prompt.contains("No tasks recorded."))
    }

    func testWeeklyReviewPromptContainsStructure() {
        let prompt = AIPromptBuilder.weeklyReviewPrompt(
            weekSummary: "test",
            averageMood: 4.0,
            totalTasks: 5,
            completedTasks: 3,
            streak: 2
        )

        // Should contain structural instructions
        XCTAssertTrue(prompt.contains("pattern"))
        XCTAssertTrue(prompt.contains("suggestion"))
        XCTAssertTrue(prompt.contains("150 words"))
    }
}
