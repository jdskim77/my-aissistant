import XCTest
@testable import MyAIssistant

final class KeychainServiceTests: XCTestCase {

    private var sut: MockKeychainService!

    override func setUp() {
        super.setUp()
        sut = MockKeychainService()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Basic CRUD

    func testSaveAndRead() {
        let saved = sut.save(key: "test-key", value: "test-value")
        XCTAssertTrue(saved)

        let read = sut.read(key: "test-key")
        XCTAssertEqual(read, "test-value")
    }

    func testReadNonExistentKey() {
        let read = sut.read(key: "nonexistent")
        XCTAssertNil(read)
    }

    func testDelete() {
        sut.save(key: "test-key", value: "test-value")
        let deleted = sut.delete(key: "test-key")
        XCTAssertTrue(deleted)

        let read = sut.read(key: "test-key")
        XCTAssertNil(read)
    }

    func testOverwriteExistingKey() {
        sut.save(key: "test-key", value: "original")
        sut.save(key: "test-key", value: "updated")

        let read = sut.read(key: "test-key")
        XCTAssertEqual(read, "updated")
    }

    // MARK: - Anthropic API Key

    func testAnthropicAPIKeyConvenience() {
        sut.setAnthropicKey("sk-ant-test")
        let key = sut.read(key: AppConstants.anthropicAPIKeyKey)
        XCTAssertEqual(key, "sk-ant-test")
    }

    func testAnthropicAPIKeyReadConvenience() {
        sut.setAnthropicKey("my-api-key")
        let key = sut.anthropicAPIKey()
        XCTAssertEqual(key, "my-api-key")
    }

    func testAnthropicAPIKeyNilWhenNotSet() {
        let key = sut.anthropicAPIKey()
        XCTAssertNil(key)
    }

    func testSaveAnthropicAPIKey() {
        let result = sut.saveAnthropicAPIKey("new-key")
        XCTAssertTrue(result)
        XCTAssertEqual(sut.anthropicAPIKey(), "new-key")
    }

    // MARK: - OpenAI API Key

    func testOpenAIAPIKeyConvenience() {
        sut.setOpenAIKey("sk-openai-test")
        let key = sut.read(key: AppConstants.openAIAPIKeyKey)
        XCTAssertEqual(key, "sk-openai-test")
    }

    func testOpenAIAPIKeyReadConvenience() {
        sut.setOpenAIKey("openai-key")
        let key = sut.openAIAPIKey()
        XCTAssertEqual(key, "openai-key")
    }

    func testOpenAIAPIKeyNilWhenNotSet() {
        let key = sut.openAIAPIKey()
        XCTAssertNil(key)
    }

    func testSaveOpenAIAPIKey() {
        let result = sut.saveOpenAIAPIKey("new-openai-key")
        XCTAssertTrue(result)
        XCTAssertEqual(sut.openAIAPIKey(), "new-openai-key")
    }

    // MARK: - Multiple Keys

    func testMultipleKeysIndependent() {
        sut.save(key: "key1", value: "value1")
        sut.save(key: "key2", value: "value2")

        XCTAssertEqual(sut.read(key: "key1"), "value1")
        XCTAssertEqual(sut.read(key: "key2"), "value2")

        sut.delete(key: "key1")
        XCTAssertNil(sut.read(key: "key1"))
        XCTAssertEqual(sut.read(key: "key2"), "value2")
    }

    // MARK: - Empty Values

    func testSaveEmptyString() {
        sut.save(key: "empty", value: "")
        let read = sut.read(key: "empty")
        XCTAssertEqual(read, "")
    }
}
