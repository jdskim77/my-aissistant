import XCTest

/// Source-text guard: `wipeAllLocalData()` (account deletion — Apple
/// compliance requires every on-device record to be gone) and
/// `performWipeAllData()` (dev "Wipe Everything") must wipe every
/// `@Model` type listed in `SchemaV1.models`, the single source of
/// truth for "every model currently shipped" (see SchemaVersioning.swift).
///
/// Round-2 found both wipe functions missing `CheckInPreference`,
/// `CheckInBehavior`, `CheckInSuggestion`, and `Nudge` — added to
/// SchemaV1 after the wipe functions were written, so deleting your
/// account (or using dev "Wipe Everything") left check-in scheduling
/// preferences/behavior history and nudge records behind on-device.
/// Not unit-testable directly (SettingsView's wipe helpers are
/// `private` on a SwiftUI View with no host), so this guards the
/// invariant in source. If a legitimate new @Model is added, update
/// BOTH the model list in SchemaV1 AND both wipe functions together.
final class WipeAllDataCoversSchemaSourceGuardTests: XCTestCase {

    private func locateSourceFile(named components: [String]) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            var candidate = dir.appendingPathComponent("MyAIssistant")
            for component in components {
                candidate = candidate.appendingPathComponent(component)
            }
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw XCTSkip("Could not locate \(components.joined(separator: "/")) by walking up from #filePath")
    }

    /// Pull every `Foo.self,` entry out of `SchemaV1.models`'s array literal.
    private func schemaV1ModelNames(from source: String) throws -> [String] {
        // Anchor on the full `models` property signature, not just the enum
        // opener — `enum SchemaV1: VersionedSchema {` is immediately followed
        // by `static var models: [any PersistentModel.Type] {`, and a naive
        // search for the next "[" from the enum opener matches the return
        // type's brackets instead of the array literal, yielding zero models
        // and a false-negative "both wipe functions are compliant" result.
        guard let startRange = source.range(of: "static var models: [any PersistentModel.Type] {"),
              let arrayStart = source.range(of: "[", range: startRange.upperBound..<source.endIndex),
              let arrayEnd = source.range(of: "]", range: arrayStart.upperBound..<source.endIndex) else {
            XCTFail("Could not locate SchemaV1.models array literal")
            return []
        }
        let body = source[arrayStart.upperBound..<arrayEnd.lowerBound]
        return body
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasSuffix(".self,") || trimmed.hasSuffix(".self") else { return nil }
                return String(trimmed.replacingOccurrences(of: ".self,", with: "")
                    .replacingOccurrences(of: ".self", with: ""))
            }
    }

    /// Pull every `wipe(Foo.self)` call out of a function body between
    /// `funcSignature` and the first `\n    }` dedent after it.
    private func wipedModelNames(in source: String, funcSignature: String) throws -> [String] {
        guard let funcRange = source.range(of: funcSignature) else {
            XCTFail("Could not locate \(funcSignature)")
            return []
        }
        let tail = source[funcRange.upperBound...]
        guard let endRange = tail.range(of: "\n    }") else {
            XCTFail("Could not find end of \(funcSignature)")
            return []
        }
        let body = String(tail[tail.startIndex..<endRange.lowerBound])
        // Strip `//` line comments first — a regex scan over raw source
        // would otherwise treat a commented-out `wipe(Foo.self)` call as
        // live coverage and pass even though the line no longer executes.
        let activeLines = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                if let commentIndex = line.range(of: "//")?.lowerBound {
                    return line[line.startIndex..<commentIndex]
                }
                return line
            }
            .joined(separator: "\n")
        let pattern = #"wipe\(([A-Za-z0-9_]+)\.self\)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let nsBody = activeLines as NSString
        let matches = regex.matches(in: activeLines, range: NSRange(location: 0, length: nsBody.length))
        return matches.map { nsBody.substring(with: $0.range(at: 1)) }
    }

    func testWipeAllLocalDataCoversEveryModelInSchemaV1() throws {
        let schemaSource = try locateSourceFile(named: ["Models", "SchemaVersioning.swift"])
        let settingsSource = try locateSourceFile(named: ["Views", "Settings", "SettingsView.swift"])

        let schemaModels = Set(try schemaV1ModelNames(from: schemaSource))
        XCTAssertFalse(schemaModels.isEmpty, "Sanity: should have parsed at least one model name from SchemaV1")

        let wiped = Set(try wipedModelNames(in: settingsSource, funcSignature: "private func wipeAllLocalData() throws {"))

        let missing = schemaModels.subtracting(wiped)
        XCTAssertTrue(
            missing.isEmpty,
            "wipeAllLocalData() (account deletion) must wipe every SchemaV1 model but is missing: \(missing.sorted()). " +
            "Account deletion leaving these on-device is an Apple compliance gap."
        )
    }

    func testPerformWipeAllDataCoversEveryModelInSchemaV1() throws {
        let schemaSource = try locateSourceFile(named: ["Models", "SchemaVersioning.swift"])
        let settingsSource = try locateSourceFile(named: ["Views", "Settings", "SettingsView.swift"])

        let schemaModels = Set(try schemaV1ModelNames(from: schemaSource))
        XCTAssertFalse(schemaModels.isEmpty, "Sanity: should have parsed at least one model name from SchemaV1")

        let wiped = Set(try wipedModelNames(in: settingsSource, funcSignature: "private func performWipeAllData() {"))

        let missing = schemaModels.subtracting(wiped)
        XCTAssertTrue(
            missing.isEmpty,
            "performWipeAllData() (dev 'Wipe Everything') must wipe every SchemaV1 model but is missing: \(missing.sorted())"
        )
    }
}
