import XCTest
@testable import MyAIssistant

@MainActor
final class SpeechSynthesizerTests: XCTestCase {

    private var sut: SpeechSynthesizer!

    override func setUp() async throws {
        sut = SpeechSynthesizer()
    }

    override func tearDown() async throws {
        sut.stop()
        sut = nil
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertFalse(sut.isSpeaking)
        XCTAssertNil(sut.selectedVoiceIdentifier)
    }

    // MARK: - Stop When Not Speaking

    func testStopWhenNotSpeaking() {
        // Should not crash
        sut.stop()
        XCTAssertFalse(sut.isSpeaking)
    }

    // MARK: - Voice Selection

    func testSelectedVoiceIdentifier() {
        XCTAssertNil(sut.selectedVoiceIdentifier)
        sut.selectedVoiceIdentifier = "com.apple.voice.premium.en-US.Zoe"
        XCTAssertEqual(sut.selectedVoiceIdentifier, "com.apple.voice.premium.en-US.Zoe")
    }

    // MARK: - Callback Assignment

    func testOnFinishedSpeakingCallback() {
        var callbackFired = false
        sut.onFinishedSpeaking = { callbackFired = true }
        XCTAssertFalse(callbackFired)
        XCTAssertNotNil(sut.onFinishedSpeaking)
    }

    // MARK: - Best Available Voice

    func testBestAvailableVoiceReturnsVoice() {
        let voice = SpeechSynthesizer.bestAvailableVoice()
        // Should return some voice — we can't guarantee quality tier in test environment
        XCTAssertNotNil(voice)
        XCTAssertTrue(voice.language.hasPrefix("en"))
    }
}
