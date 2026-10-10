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

        // Should contain structural instructions. Commit 688a281 (Life
        // Compass phase 1) reworded bullet #2 from "pattern" to "life
        // balance across dimensions" — this test still asserted the old
        // wording and never caught up, so it failed against correct,
        // intentional prompt copy. Assert the current structural anchors.
        XCTAssertTrue(prompt.contains("life balance"))
        XCTAssertTrue(prompt.contains("suggestion"))
        XCTAssertTrue(prompt.contains("150 words"))
    }

    // MARK: - Evening Reflection Prompt (Evening Flow redesign)

    func test_eveningReflectionPrompt_includesRatings() {
        let prompt = AIPromptBuilder.eveningReflectionPrompt(
            ratings: ["physical": 4, "mental": 3],
            energyRating: 2
        )
        XCTAssertTrue(prompt.contains("physical: 4/5"))
        XCTAssertTrue(prompt.contains("mental: 3/5"))
        XCTAssertTrue(prompt.contains("Energy: +2"))
    }

    func test_eveningReflectionPrompt_instructsOneReflectionAtMostTwoSentencesPlusQuestion() {
        let prompt = AIPromptBuilder.eveningReflectionPrompt(
            ratings: ["physical": 4],
            energyRating: nil
        )
        XCTAssertTrue(prompt.contains("ONE reflection"))
        XCTAssertTrue(prompt.contains("At most 2 sentences"))
        XCTAssertTrue(prompt.contains("one question"))
    }

    func test_eveningReflectionPrompt_neverCheerleads() {
        let prompt = AIPromptBuilder.eveningReflectionPrompt(
            ratings: ["physical": 4],
            energyRating: nil
        )
        XCTAssertTrue(prompt.contains("Never cheerlead"))
    }

    /// Product rule: a low rating must never produce celebratory wording
    /// in the instruction — no "Great job" after a low mood.
    func test_eveningReflectionPrompt_lowRating_addsGentleAcknowledgementNoCelebration() {
        let prompt = AIPromptBuilder.eveningReflectionPrompt(
            ratings: ["physical": 1, "mental": 4],
            energyRating: -2
        )
        // The prompt names "Great job" explicitly as an example of what NOT
        // to say — that's expected (it's the forbidden phrase, quoted as an
        // instruction to the model), not celebratory language itself.
        XCTAssertTrue(prompt.lowercased().contains("rated low"))
        XCTAssertTrue(prompt.contains("do NOT say things like \"Great job\""))
        XCTAssertTrue(prompt.lowercased().contains("no celebratory"))
    }

    func test_eveningReflectionPrompt_noLowRating_omitsLowRatingClause() {
        let prompt = AIPromptBuilder.eveningReflectionPrompt(
            ratings: ["physical": 4, "mental": 5],
            energyRating: 3
        )
        XCTAssertFalse(prompt.contains("rated low"))
    }
}
