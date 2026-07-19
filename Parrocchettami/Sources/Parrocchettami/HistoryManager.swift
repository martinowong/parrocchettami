import Foundation

struct HistoryEntry: Identifiable, Codable {
    let id: UUID
    var fileName: String
    var text: String
    let originalText: String
    let words: [TimedWord]
    let frameSec: Double
    let date: Date
    let audioDuration: TimeInterval?
    var isArchived: Bool
    var languageCode: String
    var languageName: String
    var outputFormat: OutputFormat
    var grouping: Double
    var richTextData: Data?
    let sourceFileName: String?

    init(
        id: UUID,
        fileName: String,
        text: String,
        originalText: String? = nil,
        words: [TimedWord],
        frameSec: Double,
        date: Date,
        audioDuration: TimeInterval?,
        isArchived: Bool = false,
        languageCode: String = "",
        languageName: String = "Auto-detect",
        outputFormat: OutputFormat = .markdown,
        grouping: Double = 0.5,
        richTextData: Data? = nil,
        sourceFileName: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.text = text
        self.originalText = originalText ?? text
        self.words = words
        self.frameSec = frameSec
        self.date = date
        self.audioDuration = audioDuration
        self.isArchived = isArchived
        self.languageCode = languageCode
        self.languageName = languageName
        self.outputFormat = outputFormat
        self.grouping = grouping
        self.richTextData = richTextData
        self.sourceFileName = sourceFileName
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case fileName
        case text
        case originalText
        case words
        case frameSec
        case date
        case audioDuration
        case isArchived
        case languageCode
        case languageName
        case outputFormat
        case grouping
        case richTextData
        case sourceFileName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        text = try container.decode(String.self, forKey: .text)
        originalText = try container.decodeIfPresent(String.self, forKey: .originalText) ?? text
        words = try container.decode([TimedWord].self, forKey: .words)
        frameSec = try container.decode(Double.self, forKey: .frameSec)
        date = try container.decode(Date.self, forKey: .date)
        audioDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .audioDuration)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode) ?? ""
        languageName = try container.decodeIfPresent(String.self, forKey: .languageName) ?? "Auto-detect"
        outputFormat = try container.decodeIfPresent(OutputFormat.self, forKey: .outputFormat) ?? .markdown
        grouping = try container.decodeIfPresent(Double.self, forKey: .grouping) ?? 0.5
        richTextData = try container.decodeIfPresent(Data.self, forKey: .richTextData)
        sourceFileName = try container.decodeIfPresent(String.self, forKey: .sourceFileName)
    }

    var result: TranscriptionResult {
        TranscriptionResult(text: text, words: words, frameSec: frameSec)
    }

    var formattedDate: String {
        Self.dateFormatter.string(from: date)
    }

    var preview: String {
        Self.preview(in: text)
    }

    func searchPreview(for query: String) -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty,
              let range = text.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return preview
        }

        let prefixStart = text.index(range.lowerBound, offsetBy: -36, limitedBy: text.startIndex) ?? text.startIndex
        let suffixEnd = text.index(range.upperBound, offsetBy: 56, limitedBy: text.endIndex) ?? text.endIndex
        let excerpt = text[prefixStart..<suffixEnd]
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefixStart == text.startIndex ? "" : "…")\(excerpt)\(suffixEnd == text.endIndex ? "" : "…")"
    }

    static func suggestedTitle(from text: String, fallback: String) -> String {
        let words = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return fallback }
        let title = words.prefix(8).joined(separator: " ")
        return words.count > 8 ? "\(title)…" : title
    }

    private static func preview(in text: String) -> String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > 72 else { return flattened }
        return "\(flattened.prefix(72))…"
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
    private var retentionLimit: Int

    init(storageURL: URL? = nil, retentionLimit: Int? = nil) {
        self.retentionLimit = retentionLimit
            ?? UserDefaults.standard.object(forKey: "historyRetentionLimit") as? Int
            ?? 100
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
    func add(
        from result: TranscriptionResult,
        fileName: String,
        audioDuration: TimeInterval? = nil,
        languageCode: String = "",
        languageName: String = "Auto-detect",
        outputFormat: OutputFormat = .markdown,
        grouping: Double = 0.5,
        sourceFileName: String? = nil
    ) -> HistoryEntry {
        let entry = HistoryEntry(
            id: UUID(),
            fileName: fileName,
            text: result.text,
            words: result.words,
            frameSec: result.frameSec,
            date: Date(),
            audioDuration: audioDuration,
            languageCode: languageCode,
            languageName: languageName,
            outputFormat: outputFormat,
            grouping: grouping,
            sourceFileName: sourceFileName
        )
        entries.insert(entry, at: 0)
        trimToRetentionLimit()
        save()
        return entry
    }

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func archive(_ entry: HistoryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updatedEntries = entries
        updatedEntries[index].isArchived = true
        entries = updatedEntries
        save()
    }

    func restore(_ entry: HistoryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updatedEntries = entries
        var restoredEntry = updatedEntries.remove(at: index)
        restoredEntry.isArchived = false
        updatedEntries.insert(restoredEntry, at: 0)
        entries = updatedEntries
        trimToRetentionLimit()
        save()
    }

    func rename(_ entry: HistoryEntry, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }

        var updatedEntries = entries
        updatedEntries[index].fileName = trimmedName
        entries = updatedEntries
        save()
    }

    func updateTranscript(_ entry: HistoryEntry, text: String, richTextData: Data?) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updatedEntries = entries
        updatedEntries[index].text = text
        updatedEntries[index].richTextData = richTextData
        entries = updatedEntries
        save()
    }

    func updatePresentation(_ entry: HistoryEntry, format: OutputFormat, grouping: Double) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updatedEntries = entries
        updatedEntries[index].outputFormat = format
        updatedEntries[index].grouping = grouping
        entries = updatedEntries
        save()
    }

    func updateRetentionLimit(_ newLimit: Int) {
        retentionLimit = max(0, newLimit)
        trimToRetentionLimit()
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
            trimToRetentionLimit()
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

    private func trimToRetentionLimit() {
        guard retentionLimit > 0 else { return }
        let activeEntries = entries.filter { !$0.isArchived }
        guard activeEntries.count > retentionLimit else { return }
        let retainedActiveIDs = Set(activeEntries.prefix(retentionLimit).map(\.id))
        entries.removeAll { !$0.isArchived && !retainedActiveIDs.contains($0.id) }
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
