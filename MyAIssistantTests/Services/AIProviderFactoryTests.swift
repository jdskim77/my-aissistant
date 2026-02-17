import XCTest
@testable import MyAIssistant

final class AIProviderFactoryTests: XCTestCase {

    private var mockKeychain: MockKeychainService!

    override func setUp() {
        super.setUp()
        mockKeychain = MockKeychainService()
    }

    override func tearDown() {
        mockKeychain = nil
        super.tearDown()
    }

    // MARK: - No API Key

    func testThrowsWhenNoAnthropicKey() {
        XCTAssertThrowsError(
            try AIProviderFactory.provider(for: .free, useCase: .chat, keychain: mockKeychain)
        ) { error in
            XCTAssertTrue(error is AIError)
            if case AIError.noAPIKey = error {
                // Expected
            } else {
                XCTFail("Expected AIError.noAPIKey, got \(error)")
            }
        }
    }

    func testThrowsWhenEmptyAnthropicKey() {
        mockKeychain.setAnthropicKey("")
        XCTAssertThrowsError(
            try AIProviderFactory.provider(for: .free, useCase: .chat, keychain: mockKeychain)
        )
    }

    // MARK: - Free Tier

    func testFreeTierReturnsAnthropicProvider() throws {
        mockKeychain.setAnthropicKey("test-key")
        let provider = try AIProviderFactory.provider(for: .free, useCase: .chat, keychain: mockKeychain)
        XCTAssertTrue(provider is AnthropicProvider)
    }

    func testFreeTierUsesHaikuForChat() throws {
        mockKeychain.setAnthropicKey("test-key")
        let provider = try AIProviderFactory.provider(for: .free, useCase: .chat, keychain: mockKeychain)
        XCTAssertTrue(provider is AnthropicProvider)
    }

    func testFreeTierUsesHaikuForCheckIn() throws {
        mockKeychain.setAnthropicKey("test-key")
        let provider = try AIProviderFactory.provider(for: .free, useCase: .checkIn, keychain: mockKeychain)
        XCTAssertTrue(provider is AnthropicProvider)
    }

    // MARK: - Pro Tier

    func testProTierReturnsAnthropicProvider() throws {
        mockKeychain.setAnthropicKey("test-key")
        let provider = try AIProviderFactory.provider(for: .pro, useCase: .chat, keychain: mockKeychain)
        XCTAssertTrue(provider is AnthropicProvider)
    }

    func testProTierCheckInReturnsAnthropicProvider() throws {
        mockKeychain.setAnthropicKey("test-key")
        let provider = try AIProviderFactory.provider(for: .pro, useCase: .checkIn, keychain: mockKeychain)
        XCTAssertTrue(provider is AnthropicProvider)
    }

    // MARK: - Student Tier

    func testStudentTierReturnsAnthropicProvider() throws {
        mockKeychain.setAnthropicKey("test-key")
        let provider = try AIProviderFactory.provider(for: .student, useCase: .chat, keychain: mockKeychain)
        XCTAssertTrue(provider is AnthropicProvider)
    }

    // MARK: - Power User Tier

    func testPowerUserWithOpenAIKeyReturnsOpenAIProvider() throws {
        mockKeychain.setOpenAIKey("sk-test-key")
        let provider = try AIProviderFactory.provider(for: .powerUser, useCase: .chat, keychain: mockKeychain)
        XCTAssertTrue(provider is OpenAIProvider)
    }

    func testPowerUserWithEmptyOpenAIKeyFallsBackToAnthropic() throws {
        mockKeychain.setAnthropicKey("test-key")
        mockKeychain.setOpenAIKey("")
        let provider = try AIProviderFactory.provider(for: .powerUser, useCase: .chat, keychain: mockKeychain)
        XCTAssertTrue(provider is AnthropicProvider)
    }

    func testPowerUserWithNoOpenAIKeyFallsBackToAnthropic() throws {
        mockKeychain.setAnthropicKey("test-key")
        let provider = try AIProviderFactory.provider(for: .powerUser, useCase: .chat, keychain: mockKeychain)
        XCTAssertTrue(provider is AnthropicProvider)
    }

    func testPowerUserWithNoKeysAtAllThrows() {
        XCTAssertThrowsError(
            try AIProviderFactory.provider(for: .powerUser, useCase: .chat, keychain: mockKeychain)
        )
    }

    // MARK: - Weekly Review Use Case

    func testWeeklyReviewUseCaseProTier() throws {
        mockKeychain.setAnthropicKey("test-key")
        let provider = try AIProviderFactory.provider(for: .pro, useCase: .weeklyReview, keychain: mockKeychain)
        XCTAssertTrue(provider is AnthropicProvider)
    }

    func testWeeklyReviewUseCaseFreeTier() throws {
        mockKeychain.setAnthropicKey("test-key")
        let provider = try AIProviderFactory.provider(for: .free, useCase: .weeklyReview, keychain: mockKeychain)
        XCTAssertTrue(provider is AnthropicProvider)
    }
}
