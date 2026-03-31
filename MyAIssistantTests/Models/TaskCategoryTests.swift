import XCTest
@testable import MyAIssistant

final class TaskCategoryTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(TaskCategory.allCases.count, 5)
    }

    func testRawValues() {
        XCTAssertEqual(TaskCategory.travel.rawValue, "Travel")
        XCTAssertEqual(TaskCategory.errand.rawValue, "Errand")
        XCTAssertEqual(TaskCategory.personal.rawValue, "Personal")
        XCTAssertEqual(TaskCategory.work.rawValue, "Work")
        XCTAssertEqual(TaskCategory.health.rawValue, "Health")
    }

    func testIcons() {
        for category in TaskCategory.allCases {
            XCTAssertFalse(category.icon.isEmpty, "\(category.rawValue) should have an icon")
        }
    }

    func testIdentifiable() {
        for category in TaskCategory.allCases {
            XCTAssertEqual(category.id, category.rawValue)
        }
    }

    func testCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for category in TaskCategory.allCases {
            let data = try encoder.encode(category)
            let decoded = try decoder.decode(TaskCategory.self, from: data)
            XCTAssertEqual(decoded, category)
        }
    }
}
