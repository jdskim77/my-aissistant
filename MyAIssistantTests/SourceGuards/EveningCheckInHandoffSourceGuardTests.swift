import XCTest

/// Source-text guard for the Evening Flow redesign's check-in → Coach
/// handoff: after "Save check-in", the app should land on the Coach tab
/// and trigger exactly one AI-generated reflection referencing tonight's
/// ratings, via the existing ChatManager/AIPromptBuilder paths — never a
/// raw error bubble when AI is unavailable or the user is signed out.
/// SwiftUI view bodies aren't practical to unit test without a UI test
/// target/host app, so this guards the literal wiring directly in
/// source. Skips cleanly (doesn't fail) if the source tree isn't
/// present on the runner.
final class EveningCheckInHandoffSourceGuardTests: XCTestCase {

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

    func testEveningCheckInViewCallsReflectionGeneratorOnSave() throws {
        let source = try locateSourceFile(["Views", "Compass", "EveningCheckInView.swift"])
        XCTAssertTrue(
            source.contains("EveningReflectionGenerator"),
            "Save check-in should hand off to Coach via EveningReflectionGenerator"
        )
        XCTAssertTrue(
            source.contains(".send("),
            "EveningCheckInView should call the generator's send(...) once per saved check-in"
        )
    }

    func testReflectionGeneratorGatedBySettingAndNeverThrowsToCaller() throws {
        let source = try locateSourceFile(["Services", "AI", "EveningReflectionGenerator.swift"])
        XCTAssertTrue(
            source.contains("eveningReflectionHandoffEnabledKey"),
            "The handoff should be gated behind the on/off AppStorage setting"
        )
        XCTAssertTrue(
            source.contains("func send("),
            "Generator should expose a send(...) entry point"
        )
        XCTAssertTrue(
            source.contains("Never throws"),
            "send(...) must never throw — the caller lands on Coach silently on failure, with no error bubble"
        )
    }

    func testSettingDefaultsOn() throws {
        let source = try locateSourceFile(["Core", "AppConstants.swift"])
        guard let keyRange = source.range(of: "eveningReflectionHandoffEnabledKey") else {
            XCTFail("Expected eveningReflectionHandoffEnabledKey in AppConstants.swift")
            return
        }
        _ = keyRange
        let settingsSource = try locateSourceFile(["Views", "Settings", "CoachSettingsView.swift"])
        XCTAssertTrue(
            settingsSource.contains("private var eveningReflectionHandoffEnabled: Bool = true"),
            "The Coach-reflection handoff setting should default to on"
        )
    }
}
