import Foundation

struct HistoryEntry: Identifiable, Codable {
    let id: UUID
    var fileName: String
    let text: String
    let words: [TimedWord]
    let frameSec: Double
    let date: Date
    let audioDuration: TimeInterval?
    let isArchived: Bool

    init(
        id: UUID,
        fileName: String,
        text: String,
        words: [TimedWord],
        frameSec: Double,
        date: Date,
        audioDuration: TimeInterval?,
        isArchived: Bool = false
    ) {
        self.id = id
        self.fileName = fileName
        self.text = text
        self.words = words
        self.frameSec = frameSec
        self.date = date
        self.audioDuration = audioDuration
        self.isArchived = isArchived
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case fileName
        case text
        case words
        case frameSec
        case date
        case audioDuration
        case isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        text = try container.decode(String.self, forKey: .text)
        words = try container.decode([TimedWord].self, forKey: .words)
        frameSec = try container.decode(Double.self, forKey: .frameSec)
        date = try container.decode(Date.self, forKey: .date)
        audioDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .audioDuration)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    var result: TranscriptionResult {
        TranscriptionResult(text: text, words: words, frameSec: frameSec)
    }

    var formattedDate: String {
        Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

class HistoryManager: ObservableObject {
    @Published var entries: [HistoryEntry] = []
    @Published private(set) var lastError: String?

    private let storageURL: URL

    init(storageURL: URL? = nil) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let dir = appSupport.appendingPathComponent("Parrocchettami")
            self.storageURL = dir.appendingPathComponent("history.json")

            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                setRestrictivePermissions(directory: dir)
            } catch {
                lastError = "Cannot create history folder: \(error.localizedDescription)"
            }
        }
        load()
    }

    @discardableResult
    func add(from result: TranscriptionResult, fileName: String, audioDuration: TimeInterval? = nil) -> HistoryEntry {
        let entry = HistoryEntry(
            id: UUID(),
            fileName: fileName,
            text: result.text,
            words: result.words,
            frameSec: result.frameSec,
            date: Date(),
            audioDuration: audioDuration
        )
        entries.insert(entry, at: 0)
        if entries.count > 100 { entries = Array(entries.prefix(100)) }
        save()
        return entry
    }

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func archive(_ entry: HistoryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = HistoryEntry(
            id: entry.id,
            fileName: entry.fileName,
            text: entry.text,
            words: entry.words,
            frameSec: entry.frameSec,
            date: entry.date,
            audioDuration: entry.audioDuration,
            isArchived: true
        )
        save()
    }

    func rename(_ entry: HistoryEntry, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }

        entries[index].fileName = trimmedName
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
            lastError = nil
        } catch {
            lastError = "Cannot load transcription history: \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            setRestrictivePermissions(directory: storageURL.deletingLastPathComponent())
            let data = try JSONEncoder().encode(entries)
            try data.write(to: storageURL, options: .atomic)
            setRestrictiveFilePermissions()
            lastError = nil
        } catch {
            lastError = "Cannot save transcription history: \(error.localizedDescription)"
        }
    }

    private func setRestrictivePermissions(directory: URL) {
        let attrs: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: 0o700)]
        try? FileManager.default.setAttributes(attrs, ofItemAtPath: directory.path)
    }

    private func setRestrictiveFilePermissions() {
        let attrs: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: 0o600)]
        try? FileManager.default.setAttributes(attrs, ofItemAtPath: storageURL.path)
    }
}
