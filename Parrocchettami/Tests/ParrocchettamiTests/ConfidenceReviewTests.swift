import XCTest
@testable import Parrocchettami

final class ConfidenceReviewTests: XCTestCase {
    func testLowConfidenceWordsUseDefaultThreshold() {
        let words = [
            TimedWord(w: "certain", start: 0, end: 0.2, conf: 0.96),
            TimedWord(w: "unclear", start: 0.3, end: 0.6, conf: 0.55)
        ]

        XCTAssertEqual(ConfidenceReview.lowConfidenceWords(in: words).map(\.w), ["unclear"])
    }

    func testRangesFollowRepeatedWordsInOrder() {
        let text = "hello hello world"
        let words = [
            TimedWord(w: "hello", start: 0, end: 0.2, conf: 0.95),
            TimedWord(w: "hello", start: 0.3, end: 0.5, conf: 0.4),
            TimedWord(w: "world", start: 0.6, end: 0.9, conf: 0.3)
        ]

        let ranges = ConfidenceReview.ranges(in: text, words: words)
        XCTAssertEqual(ranges.map { String(text[$0]) }, ["hello", "world"])
        XCTAssertEqual(ranges.first?.lowerBound, text.index(text.startIndex, offsetBy: 6))
    }
}
