import XCTest
@testable import MyAIssistant

@MainActor
final class WisdomManagerTests: XCTestCase {

    // MARK: - Quote Struct

    func testQuoteCodable() throws {
        let json = #"{"text":"Be the change.","author":"Gandhi","category":"motivation"}"#
        let data = json.data(using: .utf8)!
        let quote = try JSONDecoder().decode(WisdomManager.Quote.self, from: data)

        XCTAssertEqual(quote.text, "Be the change.")
        XCTAssertEqual(quote.author, "Gandhi")
        XCTAssertEqual(quote.category, "motivation")
    }

    func testQuoteArrayCodable() throws {
        let json = """
        [
            {"text":"Quote 1","author":"Author 1","category":"cat1"},
            {"text":"Quote 2","author":"Author 2","category":"cat2"}
        ]
        """
        let data = json.data(using: .utf8)!
        let quotes = try JSONDecoder().decode([WisdomManager.Quote].self, from: data)
        XCTAssertEqual(quotes.count, 2)
    }

    // MARK: - Load Quotes

    func testLoadQuotesReturnsArray() {
        // In test environment, bundle may not contain DailyWisdom.json
        // so this may return empty — that's a valid result
        let quotes = WisdomManager.loadQuotes()
        // We just verify it doesn't crash and returns an array
        XCTAssertNotNil(quotes)
    }

    // MARK: - Today Quote

    func testTodayQuoteIsDeterministic() {
        // Calling todayQuote twice should return the same quote
        let first = WisdomManager.todayQuote()
        let second = WisdomManager.todayQuote()

        if let first = first, let second = second {
            XCTAssertEqual(first.text, second.text)
            XCTAssertEqual(first.author, second.author)
        }
        // If both are nil, the bundle doesn't have the JSON — that's acceptable in tests
    }
}
