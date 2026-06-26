import XCTest
@testable import Parrocchettami

final class TranscriptSearchTests: XCTestCase {
    func testMatchCountIgnoresCaseAndDiacritics() {
        XCTAssertEqual(
            TranscriptSearch.matchCount(in: "Cafe cafe CAFÉ", query: " café "),
            3
        )
    }

    func testMatchCountIgnoresEmptyQueries() {
        XCTAssertEqual(TranscriptSearch.matchCount(in: "Hello", query: ""), 0)
        XCTAssertEqual(TranscriptSearch.matchCount(in: "Hello", query: "   "), 0)
    }

    func testMatchCountDoesNotCountOverlappingMatches() {
        XCTAssertEqual(TranscriptSearch.matchCount(in: "aaaa", query: "aa"), 2)
    }
}
