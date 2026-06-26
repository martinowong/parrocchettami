import XCTest
@testable import Parrocchettami

final class HistoryEntryTests: XCTestCase {
    func testHistoryEntryCodableRoundTrip() throws {
        let entry = HistoryEntry(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            fileName: "sample.wav",
            text: "Hello",
            words: [TimedWord(w: "Hello", start: 0, end: 0.4, conf: 0.98)],
            frameSec: 0.08,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            audioDuration: 12.5
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.fileName, "sample.wav")
        XCTAssertEqual(decoded.text, "Hello")
        XCTAssertEqual(decoded.words.first?.w, "Hello")
        XCTAssertEqual(decoded.frameSec, 0.08)
        XCTAssertEqual(decoded.date, entry.date)
        XCTAssertEqual(decoded.audioDuration, 12.5)
        XCTAssertFalse(decoded.isArchived)
    }

    func testHistoryEntryDecodesMissingArchiveFlagAsActive() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "fileName": "legacy.wav",
          "text": "Legacy transcript",
          "words": [],
          "frameSec": 0.08,
          "date": 1700000000,
          "audioDuration": 8.5
        }
        """

        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.fileName, "legacy.wav")
        XCTAssertFalse(decoded.isArchived)
    }
}
