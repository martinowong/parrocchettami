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
        XCTAssertEqual(decoded.originalText, "Hello")
        XCTAssertEqual(decoded.languageName, "Auto-detect")
        XCTAssertEqual(decoded.outputFormat, .markdown)
        XCTAssertEqual(decoded.grouping, 0.5)
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
        XCTAssertEqual(decoded.originalText, "Legacy transcript")
        XCTAssertEqual(decoded.outputFormat, .markdown)
    }

    func testRenameOnlyChangesTheTargetEntry() throws {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent()) }
        let manager = HistoryManager(storageURL: storageURL)
        let result = TranscriptionResult(text: "Example", words: [], frameSec: 0.08)
        let first = manager.add(from: result, fileName: "First")
        let second = manager.add(from: result, fileName: "Second")

        manager.rename(first, to: "Renamed First")

        XCTAssertEqual(manager.entries.first(where: { $0.id == first.id })?.fileName, "Renamed First")
        XCTAssertEqual(manager.entries.first(where: { $0.id == second.id })?.fileName, "Second")
    }

    func testTranscriptEditsAndPresentationPersist() throws {
        let storageURL = temporaryHistoryURL()
        defer { try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent()) }
        let manager = HistoryManager(storageURL: storageURL)
        let result = TranscriptionResult(text: "Original", words: [], frameSec: 0.08)
        let entry = manager.add(
            from: result,
            fileName: "Example",
            languageCode: "it",
            languageName: "Italian",
            sourceFileName: "meeting.wav"
        )

        manager.updateTranscript(entry, text: "Corrected", richTextData: Data([1, 2, 3]))
        manager.updatePresentation(entry, format: .srt, grouping: 0.8)

        let reloaded = HistoryManager(storageURL: storageURL).entries.first
        XCTAssertEqual(reloaded?.text, "Corrected")
        XCTAssertEqual(reloaded?.originalText, "Original")
        XCTAssertEqual(reloaded?.languageCode, "it")
        XCTAssertEqual(reloaded?.languageName, "Italian")
        XCTAssertEqual(reloaded?.outputFormat, .srt)
        XCTAssertEqual(reloaded?.grouping, 0.8)
        XCTAssertEqual(reloaded?.richTextData, Data([1, 2, 3]))
        XCTAssertEqual(reloaded?.sourceFileName, "meeting.wav")
    }

    func testArchiveCanBeRestored() throws {
        let storageURL = temporaryHistoryURL()
        defer { try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent()) }
        let manager = HistoryManager(storageURL: storageURL)
        let entry = manager.add(
            from: TranscriptionResult(text: "Example", words: [], frameSec: 0.08),
            fileName: "Example"
        )

        manager.archive(entry)
        XCTAssertTrue(manager.entries.first?.isArchived == true)

        manager.restore(manager.entries[0])
        XCTAssertFalse(manager.entries.first?.isArchived == true)
    }

    func testRetentionTrimsOnlyActiveEntries() throws {
        let storageURL = temporaryHistoryURL()
        defer { try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent()) }
        let manager = HistoryManager(storageURL: storageURL, retentionLimit: 2)
        let result = TranscriptionResult(text: "Example", words: [], frameSec: 0.08)
        let archived = manager.add(from: result, fileName: "Archived")
        manager.archive(archived)
        _ = manager.add(from: result, fileName: "First")
        _ = manager.add(from: result, fileName: "Second")
        _ = manager.add(from: result, fileName: "Third")

        XCTAssertEqual(manager.entries.filter { !$0.isArchived }.count, 2)
        XCTAssertEqual(manager.entries.filter(\.isArchived).count, 1)
        XCTAssertFalse(manager.entries.contains { $0.fileName == "First" })
    }

    func testSuggestedTitleUsesFirstEightWords() {
        let title = HistoryEntry.suggestedTitle(
            from: "one two three four five six seven eight nine ten",
            fallback: "Recording"
        )

        XCTAssertEqual(title, "one two three four five six seven eight…")
    }

    private func temporaryHistoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("history.json")
    }
}
