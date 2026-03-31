import XCTest
@testable import MyAIssistant

@MainActor
final class SpeechRecognizerTests: XCTestCase {

    private var sut: SpeechRecognizer!

    override func setUp() async throws {
        sut = SpeechRecognizer()
    }

    override func tearDown() async throws {
        sut = nil
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertEqual(sut.transcript, "")
        XCTAssertFalse(sut.isRecording)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.permissionGranted)
    }

    // MARK: - Default Configuration

    func testDefaultSilenceTimeout() {
        XCTAssertEqual(sut.silenceTimeout, 1.5)
    }

    func testDefaultMinimumRecordingDuration() {
        XCTAssertEqual(sut.minimumRecordingDuration, 2.0)
    }

    // MARK: - Custom Configuration

    func testCustomSilenceTimeout() {
        sut.silenceTimeout = 3.0
        XCTAssertEqual(sut.silenceTimeout, 3.0)
    }

    func testCustomMinimumRecordingDuration() {
        sut.minimumRecordingDuration = 5.0
        XCTAssertEqual(sut.minimumRecordingDuration, 5.0)
    }

    // MARK: - Stop Recording When Not Recording

    func testStopRecordingWhenNotRecording() {
        // Should not crash or change state
        sut.stopRecording()
        XCTAssertFalse(sut.isRecording)
    }

    // MARK: - Callback Assignment

    func testOnSilenceDetectedCallback() {
        var callbackFired = false
        sut.onSilenceDetected = { callbackFired = true }

        // Callback is assigned but not called yet
        XCTAssertFalse(callbackFired)
        XCTAssertNotNil(sut.onSilenceDetected)
    }

    // MARK: - Transcript State

    func testTranscriptStartsEmpty() {
        XCTAssertTrue(sut.transcript.isEmpty)
    }

    func testErrorMessageStartsNil() {
        XCTAssertNil(sut.errorMessage)
    }
}
