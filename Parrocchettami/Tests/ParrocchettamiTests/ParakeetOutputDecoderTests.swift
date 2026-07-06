import XCTest
@testable import Parrocchettami

final class ParakeetOutputDecoderTests: XCTestCase {
    func testDecodesPrettyPrintedJSONInsideNoisyOutput() throws {
        let raw = """
        ggml_backend_metal_log: noise
        {
          "text": "Hello world",
          "frame_sec": 0.08,
          "words": [
            { "w": "Hello", "start": 0.0, "end": 0.4, "conf": 0.9 },
            { "w": "world", "start": 0.5, "end": 1.0, "conf": 0.95 }
          ]
        }
        """

        let decoded = try ParakeetOutputDecoder.decode(
            ProcessOutput(terminationStatus: 0, data: Data(raw.utf8))
        )

        XCTAssertEqual(decoded.result.text, "Hello world")
        XCTAssertEqual(decoded.result.words.count, 2)
        XCTAssertEqual(decoded.result.frameSec, 0.08)
    }

    func testSkipsNonTranscriptJSONBeforeResult() throws {
        let raw = """
        log context {"event":"warmup"}
        {"text":"Final transcript","frame_sec":0.08,"words":[]}
        """

        let decoded = try ParakeetOutputDecoder.decode(
            ProcessOutput(terminationStatus: 0, data: Data(raw.utf8))
        )

        XCTAssertEqual(decoded.result.text, "Final transcript")
    }

    func testFallsBackToPlainOutputWhenJSONIsAbsent() throws {
        let decoded = try ParakeetOutputDecoder.decode(
            ProcessOutput(terminationStatus: 0, data: Data("plain transcript".utf8))
        )

        XCTAssertEqual(decoded.result.text, "plain transcript")
        XCTAssertTrue(decoded.result.words.isEmpty)
    }
}
