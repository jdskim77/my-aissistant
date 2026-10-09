import XCTest
@testable import MyAIssistant

final class MessageGroupingTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func test_sameSenderWithinWindow_isGrouped() {
        XCTAssertTrue(
            MessageGrouping.areGrouped(
                sameSender: true,
                previousTimestamp: base,
                currentTimestamp: base.addingTimeInterval(60)
            )
        )
    }

    func test_sameSenderExactlyAtWindowBoundary_isGrouped() {
        XCTAssertTrue(
            MessageGrouping.areGrouped(
                sameSender: true,
                previousTimestamp: base,
                currentTimestamp: base.addingTimeInterval(300)
            )
        )
    }

    func test_sameSenderBeyondWindow_isNotGrouped() {
        XCTAssertFalse(
            MessageGrouping.areGrouped(
                sameSender: true,
                previousTimestamp: base,
                currentTimestamp: base.addingTimeInterval(301)
            )
        )
    }

    func test_differentSenderWithinWindow_isNotGrouped() {
        XCTAssertFalse(
            MessageGrouping.areGrouped(
                sameSender: false,
                previousTimestamp: base,
                currentTimestamp: base.addingTimeInterval(1)
            )
        )
    }

    func test_outOfOrderTimestamp_stillGroupsWithinWindow() {
        // Current timestamp earlier than previous (clock skew / backfill):
        // abs() should still treat it as grouped if within the window.
        XCTAssertTrue(
            MessageGrouping.areGrouped(
                sameSender: true,
                previousTimestamp: base.addingTimeInterval(60),
                currentTimestamp: base
            )
        )
    }

    func test_timestampVisibility_firstMessageAlwaysShown() {
        let entries: [(sender: String, timestamp: Date)] = [
            (sender: "user", timestamp: base)
        ]
        XCTAssertEqual(MessageGrouping.timestampVisibility(for: entries), [true])
    }

    func test_timestampVisibility_emptyInput_returnsEmpty() {
        let entries: [(sender: String, timestamp: Date)] = []
        XCTAssertEqual(MessageGrouping.timestampVisibility(for: entries), [])
    }

    func test_timestampVisibility_groupsConsecutiveSameSenderBurst() {
        let entries: [(sender: String, timestamp: Date)] = [
            (sender: "user", timestamp: base),
            (sender: "user", timestamp: base.addingTimeInterval(30)),
            (sender: "user", timestamp: base.addingTimeInterval(90)),
        ]
        XCTAssertEqual(MessageGrouping.timestampVisibility(for: entries), [true, false, false])
    }

    func test_timestampVisibility_roleChangeAlwaysStartsNewGroup() {
        let entries: [(sender: String, timestamp: Date)] = [
            (sender: "user", timestamp: base),
            (sender: "assistant", timestamp: base.addingTimeInterval(1)),
            (sender: "user", timestamp: base.addingTimeInterval(2)),
        ]
        XCTAssertEqual(MessageGrouping.timestampVisibility(for: entries), [true, true, true])
    }

    func test_timestampVisibility_gapBeyondWindowStartsNewGroup() {
        let entries: [(sender: String, timestamp: Date)] = [
            (sender: "assistant", timestamp: base),
            (sender: "assistant", timestamp: base.addingTimeInterval(400)),
        ]
        XCTAssertEqual(MessageGrouping.timestampVisibility(for: entries), [true, true])
    }
}
