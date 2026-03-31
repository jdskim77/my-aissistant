import XCTest
@testable import MyAIssistant

final class TaskPriorityTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(TaskPriority.allCases.count, 3)
        XCTAssertTrue(TaskPriority.allCases.contains(.high))
        XCTAssertTrue(TaskPriority.allCases.contains(.medium))
        XCTAssertTrue(TaskPriority.allCases.contains(.low))
    }

    func testSortOrder() {
        XCTAssertLessThan(TaskPriority.high.sortOrder, TaskPriority.medium.sortOrder)
        XCTAssertLessThan(TaskPriority.medium.sortOrder, TaskPriority.low.sortOrder)
    }

    func testRawValues() {
        XCTAssertEqual(TaskPriority.high.rawValue, "High")
        XCTAssertEqual(TaskPriority.medium.rawValue, "Medium")
        XCTAssertEqual(TaskPriority.low.rawValue, "Low")
    }

    func testIdentifiable() {
        for priority in TaskPriority.allCases {
            XCTAssertEqual(priority.id, priority.rawValue)
        }
    }

    func testCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for priority in TaskPriority.allCases {
            let data = try encoder.encode(priority)
            let decoded = try decoder.decode(TaskPriority.self, from: data)
            XCTAssertEqual(decoded, priority)
        }
    }
}
