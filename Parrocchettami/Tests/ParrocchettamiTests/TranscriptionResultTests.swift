import XCTest
@testable import Parrocchettami

final class TranscriptionResultTests: XCTestCase {
    func testMarkdownFormattingReturnsFullText() {
        let result = TranscriptionResult(
            text: "Hello from Parrocchettami.",
            words: [],
            frameSec: 0.08
        )

        XCTAssertEqual(result.formatted(as: .markdown), "Hello from Parrocchettami.")
    }

    func testTimestampedFormattingGroupsWordsByGapAndLimit() {
        let result = TranscriptionResult(
            text: "Hello world again",
            words: [
                TimedWord(w: "Hello", start: 0.0, end: 0.2, conf: 0.9),
                TimedWord(w: "world", start: 0.25, end: 0.5, conf: 0.9),
                TimedWord(w: "again", start: 2.0, end: 2.4, conf: 0.9)
            ],
            frameSec: 0.08
        )

        XCTAssertEqual(
            result.formatted(as: .timestamped, grouping: 0.1),
            """
            [0.00-0.50] Hello world
            [2.00-2.40] again
            """
        )
    }

    func testSRTFormatting() {
        let result = TranscriptionResult(
            text: "Hello world",
            words: [
                TimedWord(w: "Hello", start: 0.0, end: 0.25, conf: 0.9),
                TimedWord(w: "world", start: 0.3, end: 1.5, conf: 0.9)
            ],
            frameSec: 0.08
        )

        XCTAssertEqual(
            result.formatted(as: .srt, grouping: 0.5),
            """
            1
            00:00:00,000 --> 00:00:01,500
            Hello world
            """
        )
    }

    func testEmptyTimedFormatsAreEmpty() {
        let result = TranscriptionResult(text: "Only plain text", words: [], frameSec: 0.08)

        XCTAssertEqual(result.formatted(as: .timestamped), "")
        XCTAssertEqual(result.formatted(as: .srt), "")
    }
}
