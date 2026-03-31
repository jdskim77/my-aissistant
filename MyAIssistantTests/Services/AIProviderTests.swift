import XCTest
@testable import MyAIssistant

final class AIProviderTests: XCTestCase {

    // MARK: - AIResponse

    func testAIResponseInit() {
        let response = AIResponse(content: "Hello!", inputTokens: 50, outputTokens: 100)
        XCTAssertEqual(response.content, "Hello!")
        XCTAssertEqual(response.inputTokens, 50)
        XCTAssertEqual(response.outputTokens, 100)
    }

    // MARK: - AIError

    func testAIErrorDescriptions() {
        XCTAssertNotNil(AIError.invalidResponse.errorDescription)
        XCTAssertNotNil(AIError.parsingError.errorDescription)
        XCTAssertNotNil(AIError.noAPIKey.errorDescription)
        XCTAssertNotNil(AIError.rateLimited.errorDescription)
    }

    func testAPIErrorDescription() {
        let error = AIError.apiError(statusCode: 401, message: "Unauthorized")
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("401"))
        XCTAssertTrue(description.contains("Unauthorized"))
    }

    func testNetworkErrorDescription() {
        let underlyingError = NSError(domain: "NSURLErrorDomain", code: -1009, userInfo: [
            NSLocalizedDescriptionKey: "The Internet connection appears to be offline."
        ])
        let error = AIError.networkError(underlyingError)
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("Network error"))
    }

    // MARK: - AIUseCase

    func testAIUseCases() {
        // Verify all use cases exist
        let _ = AIUseCase.chat
        let _ = AIUseCase.checkIn
        let _ = AIUseCase.weeklyReview
    }

    // MARK: - MockAIProvider

    func testMockProviderReturnsDefaultResponse() async throws {
        let mock = MockAIProvider()
        let response = try await mock.sendMessage(
            userMessage: "Hello",
            conversationHistory: [],
            systemPrompt: "You are helpful."
        )
        XCTAssertEqual(response.content, "Mock response")
        XCTAssertEqual(response.inputTokens, 10)
        XCTAssertEqual(response.outputTokens, 20)
    }

    func testMockProviderTracksCallCount() async throws {
        let mock = MockAIProvider()
        XCTAssertEqual(mock.sendMessageCallCount, 0)

        _ = try await mock.sendMessage(userMessage: "1", conversationHistory: [], systemPrompt: "")
        _ = try await mock.sendMessage(userMessage: "2", conversationHistory: [], systemPrompt: "")
        _ = try await mock.sendMessage(userMessage: "3", conversationHistory: [], systemPrompt: "")

        XCTAssertEqual(mock.sendMessageCallCount, 3)
    }

    func testMockProviderTracksLastMessage() async throws {
        let mock = MockAIProvider()
        _ = try await mock.sendMessage(
            userMessage: "What's the weather?",
            conversationHistory: [],
            systemPrompt: "System prompt here"
        )

        XCTAssertEqual(mock.lastUserMessage, "What's the weather?")
        XCTAssertEqual(mock.lastSystemPrompt, "System prompt here")
    }

    func testMockProviderCustomResponse() async throws {
        let mock = MockAIProvider()
        mock.responseToReturn = AIResponse(content: "Custom answer", inputTokens: 100, outputTokens: 200)

        let response = try await mock.sendMessage(userMessage: "test", conversationHistory: [], systemPrompt: "")
        XCTAssertEqual(response.content, "Custom answer")
        XCTAssertEqual(response.inputTokens, 100)
        XCTAssertEqual(response.outputTokens, 200)
    }

    func testMockProviderThrowsError() async {
        let mock = MockAIProvider()
        mock.errorToThrow = AIError.rateLimited

        do {
            _ = try await mock.sendMessage(userMessage: "test", conversationHistory: [], systemPrompt: "")
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is AIError)
            if case AIError.rateLimited = error {
                // Expected
            } else {
                XCTFail("Expected rateLimited error, got \(error)")
            }
        }
    }

    // MARK: - AnthropicProvider Initialization

    func testAnthropicProviderInit() {
        let provider = AnthropicProvider(apiKey: "test-key")
        XCTAssertNotNil(provider)
    }

    func testAnthropicProviderCustomModel() {
        let provider = AnthropicProvider(apiKey: "test-key", model: AppConstants.haikuModel)
        XCTAssertNotNil(provider)
    }

    // MARK: - OpenAIProvider Initialization

    func testOpenAIProviderInit() {
        let provider = OpenAIProvider(apiKey: "sk-test")
        XCTAssertNotNil(provider)
    }

    func testOpenAIProviderCustomModel() {
        let provider = OpenAIProvider(apiKey: "sk-test", model: "gpt-4o-mini")
        XCTAssertNotNil(provider)
    }

    // MARK: - OpenAI Vision Not Supported

    func testOpenAIVisionThrows() async {
        let provider = OpenAIProvider(apiKey: "sk-test")
        do {
            _ = try await provider.sendVisionMessage(
                prompt: "What's in this image?",
                imageData: Data(),
                mediaType: "image/png"
            )
            XCTFail("Expected error for unsupported vision")
        } catch {
            // Expected
        }
    }
}
