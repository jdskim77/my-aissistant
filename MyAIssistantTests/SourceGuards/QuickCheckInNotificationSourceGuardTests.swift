import XCTest
@testable import MyAIssistant

/// Source-text guard for Feature 1 (10-second mood check-in from the
/// notification). Confirms NotificationManager's CHECKIN/STREAK_REMINDER
/// categories include the quick-mood action identifiers and that those
/// actions are registered without `.foreground`, so tapping one completes
/// the check-in without opening the app. Also guards that the MyAIssistantApp
/// notification delegate routes those identifiers to QuickCheckInHandler
/// before the normal "open destination" switch.
final class QuickCheckInNotificationSourceGuardTests: XCTestCase {

    private func locateSourceFile(_ relativeComponents: [String]) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            var candidate = dir.appendingPathComponent("MyAIssistant")
            for component in relativeComponents {
                candidate = candidate.appendingPathComponent(component)
            }
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw XCTSkip("Could not locate \(relativeComponents.joined(separator: "/")) by walking up from #filePath")
    }

    func testCheckInCategoryIncludesAllMoodActionIdentifiers() throws {
        let source = try locateSourceFile(["Managers", "NotificationManager.swift"])
        for identifier in QuickCheckInLogic.moodActionIdentifiers {
            XCTAssertTrue(
                source.contains(identifier),
                "NotificationManager.swift should reference mood action identifier \(identifier)"
            )
        }
        XCTAssertTrue(source.contains("\"CHECKIN\""))
        XCTAssertTrue(source.contains("\"STREAK_REMINDER\""))
    }

    func testMoodActionsAreNotForeground() throws {
        let source = try locateSourceFile(["Managers", "NotificationManager.swift"])
        // The mood actions are built from QuickCheckInLogic.moodActionSpecs
        // with an explicit empty options array — assert that construction
        // site doesn't carry .foreground anywhere nearby.
        guard let range = source.range(of: "moodActionSpecs.map { spec in") else {
            XCTFail("Expected mood actions to be built from QuickCheckInLogic.moodActionSpecs")
            return
        }
        let snippetEnd = source.index(range.upperBound, offsetBy: 150, limitedBy: source.endIndex) ?? source.endIndex
        let snippet = source[range.lowerBound..<snippetEnd]
        XCTAssertFalse(snippet.contains(".foreground"), "Mood actions must not be .foreground — tapping one must not open the app")
        XCTAssertTrue(snippet.contains("options: []"))
    }

    func testStartCheckInActionRemainsForeground() throws {
        let source = try locateSourceFile(["Managers", "NotificationManager.swift"])
        XCTAssertTrue(
            source.contains("\"COMPLETE_CHECKIN\""),
            "The full-flow 'Start Check-in' action should still exist"
        )
    }

    func testAppDelegateRoutesMoodActionsBeforeDestinationSwitch() throws {
        let source = try locateSourceFile(["MyAIssistantApp.swift"])
        XCTAssertTrue(
            source.contains("QuickCheckInHandler.handle("),
            "The notification delegate should hand mood actions to QuickCheckInHandler"
        )
        guard
            let handlerRange = source.range(of: "QuickCheckInHandler.handle("),
            let destinationRange = source.range(of: "let destination: String")
        else {
            XCTFail("Expected both QuickCheckInHandler.handle( and the destination switch in MyAIssistantApp.swift")
            return
        }
        XCTAssertTrue(
            handlerRange.lowerBound < destinationRange.lowerBound,
            "Mood-action handling must run before the normal 'open destination' switch, or quick check-ins would incorrectly open the app"
        )
    }
}
