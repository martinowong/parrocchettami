import Foundation
import AVFoundation

class Transcriber: ObservableObject {
    @Published var cliReady = false
    @Published var isTranscribing = false
    @Published var transcriptionPhase: TranscriptionPhase = .idle
    @Published var transcriptionResult: TranscriptionResult?
    @Published var cliError: String?
    @Published var debugLog: String = ""
    @Published var parakeetVersion: String = "Unknown"

    private var cliPath: String?
    private var modelPath: String?
    private let processRunner = ProcessRunner()
    private let cancelLock = NSLock()
    private var pendingCancel = false

    func cancel() {
        guard isTranscribing else { return }
        cancelLock.withLock { pendingCancel = true }
        processRunner.cancel()
        isTranscribing = false
        transcriptionPhase = .idle
    }

    func locateCLI() async {
        cliReady = false
        cliError = nil
        cliPath = nil
        modelPath = nil
        var log = ""
        let candidates = cliSearchPaths()
        log += "Looking for parakeet-cli:\n"
        for path in candidates {
            let exists = FileManager.default.isExecutableFile(atPath: path)
            log += "  \(path) → \(exists ? "FOUND" : "not found")\n"
            if exists {
                cliPath = path
            }
        }
        if cliPath == nil {
            log += "NOT FOUND in any path.\n"
            cliError = "The bundled transcription engine is missing."
            debugLog = log
            parakeetVersion = "Unknown"
            return
        }
        let engineVersion = await Self.readParakeetVersion(atPath: cliPath!)
        parakeetVersion = engineVersion
        log += "Version: \(engineVersion)\n"

        let modelCandidates = modelSearchPaths()
        log += "\nLooking for model:\n"
        for path in modelCandidates {
            let exists = FileManager.default.fileExists(atPath: path)
            let isValid = exists && modelCandidateIsValid(atPath: path)
            let status = exists
                ? (isValid ? "FOUND" : "FOUND but checksum failed")
                : "not found"
            log += "  \(path) → \(status)\n"
            if isValid && modelPath == nil {
                modelPath = path
            }
        }
        if modelPath == nil {
            log += "NOT FOUND in any path.\n"
            cliError = "The speech model is not installed or failed its integrity check."
            debugLog = log
            return
        }
        cliReady = true
        cliError = nil
        log += "\nCLI: \(cliPath!)\nModel: \(modelPath!)\nREADY."
        debugLog = log
    }

    func transcribe(fileURL: URL, language: String = "") async throws -> TranscriptionResult {
        if cancelLock.withLock({ pendingCancel }) {
            throw TranscriberError.cancelled
        }

        guard let cli = cliPath, let model = modelPath else {
            let msg = "Not ready: CLI=\(cliPath ?? "nil") Model=\(modelPath ?? "nil")"
            await logError(msg)
            throw TranscriberError.notReady(msg)
        }

        await MainActor.run {
            isTranscribing = true
            transcriptionPhase = .preparing
        }
        defer {
            cancelLock.withLock { pendingCancel = false }
            Task { @MainActor in
                isTranscribing = false
                transcriptionPhase = .idle
            }
        }

        let needsScoped = fileURL.startAccessingSecurityScopedResource()
        defer { if needsScoped { fileURL.stopAccessingSecurityScopedResource() } }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("parrocchettami-transcribe-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            await logError("Failed to create temp directory: \(error.localizedDescription)")
            throw TranscriberError.processFailed("Cannot prepare temporary workspace: \(error.localizedDescription)")
        }
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let tempFile = tempDir.appendingPathComponent(fileURL.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: fileURL, to: tempFile)
        } catch {
            await logError("Failed to copy file to temp: \(error.localizedDescription)")
            throw TranscriberError.processFailed("Cannot copy audio file: \(error.localizedDescription)")
        }

        let wavFile = tempDir.appendingPathComponent("transcribe_input.wav")

        let ext = fileURL.pathExtension.lowercased()
        let inputForCLI: URL
        if ext == "wav" || ext == "wave" {
            inputForCLI = tempFile
        } else {
            do {
                await MainActor.run { transcriptionPhase = .converting }
                try await convertAudioTo16kHzMonoWAV(
                    sourceURL: tempFile,
                    destinationURL: wavFile,
                    processRunner: processRunner,
                    resourceBaseDir: resourceBaseDir(),
                    allowSystemOpusDecoderFallback: false
                )
                inputForCLI = wavFile
            } catch AudioConversionError.cancelled {
                throw TranscriberError.cancelled
            } catch {
                throw TranscriberError.processFailed("Cannot convert audio: \(error.localizedDescription)")
            }
        }

        let fileSize = (try? inputForCLI.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let logMsg = """
        Transcribing:
          Source: \(fileURL.path)
          Input:  \(inputForCLI.path) (\(ext.uppercased()) → 16kHz mono WAV)
          Size:   \(fileSize) bytes
          CLI:    \(cli)
          Model:  \(model)
        """
        await MainActor.run { debugLog = logMsg }

        var args = [
            "transcribe",
            "--model", model,
            "--input", inputForCLI.path,
            "--json",
            "--timestamps"
        ]
        if !language.isEmpty {
            args.append(contentsOf: ["--lang", language])
        }

        do {
            await MainActor.run { transcriptionPhase = .transcribing }
            let output = try await processRunner.run(
                executableURL: URL(fileURLWithPath: cli),
                arguments: args
            )
            await MainActor.run { transcriptionPhase = .formatting }
            return try await decodeParakeetOutput(output)
        } catch ProcessRunnerError.cancelled {
            throw TranscriberError.cancelled
        } catch let error as TranscriberError {
            throw error
        } catch {
            throw TranscriberError.processFailed("Cannot run parakeet-cli: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func logError(_ msg: String) {
        debugLog = msg
    }

    private func cliSearchPaths() -> [String] {
        let base = resourceBaseDir()
        return [
            "\(base)/bin/parakeet-cli",
        ]
    }

    private func modelSearchPaths() -> [String] {
        let base = resourceBaseDir()
        let names = [
            "tdt-0.6b-v3-q5_k.gguf",
            "tdt-0.6b-v3-q8_0.gguf",
            "tdt-0.6b-v3-f16.gguf",
        ]
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Parrocchettami/models").path
        return names.map { "\(appSupport)/\($0)" }
            + names.map { "\(base)/models/\($0)" }
    }

    private func modelCandidateIsValid(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard url.lastPathComponent == ModelInstaller.modelFileName else { return true }
        return ModelInstaller.modelFileIsValid(at: url)
    }

    private func resourceBaseDir() -> String {
        if let env = ProcessInfo.processInfo.environment["PARROCCHETTAMI_HOME"] {
            return env
        }
        if let resources = Bundle.main.resourceURL?.path {
            return resources
        }
        return FileManager.default.currentDirectoryPath
    }

    private static func readParakeetVersion(atPath path: String) async -> String {
        let runner = ProcessRunner()
        do {
            let output = try await runner.run(
                executableURL: URL(fileURLWithPath: path),
                arguments: ["--version"]
            )
            guard output.terminationStatus == 0 else { return "Unknown" }
            let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return "Unknown" }
            return text.components(separatedBy: .newlines).first ?? text
        } catch {
            return "Unknown"
        }
    }

    @MainActor
    private func decodeParakeetOutput(_ output: ProcessOutput) throws -> TranscriptionResult {
        let decoded = try ParakeetOutputDecoder.decode(output)
        debugLog = decoded.debugLog
        return decoded.result
    }
}

enum ParakeetOutputDecoder {
    static func decode(_ output: ProcessOutput) throws -> (result: TranscriptionResult, debugLog: String) {
        let raw = output.text
        let sanitized = sanitizeJSONOutput(raw)

        let candidates = jsonObjects(in: sanitized)

        let detail = """
        Exit code: \(output.terminationStatus)
        JSON candidates found: \(candidates.count)
        --- RAW FIRST 500 CHARS ---
        \(String(raw.prefix(500)))
        --- RAW LAST 500 CHARS ---
        \(String(raw.suffix(500)))
        """

        if output.terminationStatus != 0 {
            throw TranscriberError.processFailed(detail)
        }

        var lastJSONError: Error?
        var lastCandidatePreview: String = ""
        for jsonObject in deduplicated(candidates) {
            guard let jsonData = jsonObject.data(using: .utf8) else { continue }
            do {
                let resp = try decodeTranscriptionResponse(from: jsonData)
                return (
                    TranscriptionResult(
                        text: resp.text,
                        words: resp.words ?? [],
                        frameSec: resp.frame_sec ?? 0.08
                    ),
                    detail
                )
            } catch {
                lastJSONError = error
                lastCandidatePreview = String(jsonObject.prefix(200))
            }
        }

        if let firstCandidate = candidates.first,
           let text = extractTextField(from: firstCandidate) {
            var words: [TimedWord] = []
            if let wordsText = extractRawWordsArray(from: firstCandidate),
               let data = wordsText.data(using: .utf8),
               let parsed = try? JSONDecoder().decode([TimedWord].self, from: data) {
                words = parsed
            }
            return (
                TranscriptionResult(text: text, words: words, frameSec: 0.08),
                detail
            )
        }

        if let lastJSONError,
           candidates.contains(where: { $0.contains("\"text\"") || $0.contains("\"words\"") }) {
            throw TranscriberError.processFailed(
                "JSON parse failed: \(lastJSONError.localizedDescription)\nCandidate preview: \(lastCandidatePreview)\n\(detail)")
        }

        let plainOutput = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidates.isEmpty, !plainOutput.isEmpty {
            return (
                TranscriptionResult(text: plainOutput, words: [], frameSec: 0.08),
                detail
            )
        }

        throw TranscriberError.processFailed("No output from transcription.\n\(detail)")
    }

    private static func sanitizeJSONOutput(_ raw: String) -> String {
        raw.components(separatedBy: "\n")
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("ggml_") || trimmed.hasPrefix("[parakeet]") || trimmed.hasPrefix("main:") {
                    return ""
                }
                var cleaned = line
                for phrase in ["ggml_metal_free: deallocating", "ggml_metal_free", "ggml_metal_init:"] {
                    cleaned = cleaned.replacingOccurrences(of: phrase, with: "")
                }
                return cleaned
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func extractTextField(from jsonText: String) -> String? {
        guard let keyRange = jsonText.range(of: "\"text\"") else { return nil }
        var idx = jsonText.index(after: keyRange.upperBound)
        while idx < jsonText.endIndex, jsonText[idx].isWhitespace { idx = jsonText.index(after: idx) }
        guard idx < jsonText.endIndex, jsonText[idx] == ":" else { return nil }
        idx = jsonText.index(after: idx)
        while idx < jsonText.endIndex, jsonText[idx].isWhitespace { idx = jsonText.index(after: idx) }
        guard idx < jsonText.endIndex, jsonText[idx] == "\"" else { return nil }
        idx = jsonText.index(after: idx)

        var result = ""
        var escaped = false
        while idx < jsonText.endIndex {
            let ch = jsonText[idx]
            if escaped {
                switch ch {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "\\": result.append("\\")
                case "\"": result.append("\"")
                default: result.append(ch)
                }
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "\"" {
                return result
            } else {
                result.append(ch)
            }
            idx = jsonText.index(after: idx)
        }
        return result.isEmpty ? nil : result
    }

    private static func extractRawWordsArray(from jsonText: String) -> String? {
        guard let bracketStart = jsonText.range(of: "\"words\":[") ?? jsonText.range(of: "\"words\": [") else {
            return nil
        }
        let contentStart = jsonText[bracketStart.upperBound...]
        var depth = 1
        var inString = false
        var escaped = false
        for (offset, ch) in contentStart.enumerated() {
            if escaped { escaped = false; continue }
            if ch == "\\" { escaped = inString; continue }
            if ch == "\"" { inString.toggle(); continue }
            guard !inString else { continue }
            if ch == "[" { depth += 1 }
            else if ch == "]" {
                depth -= 1
                if depth == 0 {
                    let endIdx = contentStart.index(contentStart.startIndex, offsetBy: offset)
                    return "[" + String(contentStart[..<endIdx]) + "]"
                }
            }
        }
        return nil
    }

    private static func compactJSONFrom(lines: [String]) -> [String] {
        guard let startIdx = lines.firstIndex(where: { $0.hasPrefix("{") }),
              let endIdx = lines.lastIndex(where: { $0.hasSuffix("}") || $0.hasSuffix("]") }) else {
            return []
        }

        let jsonLines = Array(lines[startIdx...endIdx])
        let compacted = jsonLines.joined()
        return [compacted]
    }

    private static func filteredLines(from raw: String) -> [String] {
        raw.components(separatedBy: "\n")
            .map { line in
                var trimmed = line.trimmingCharacters(in: .whitespaces)
                let prefixes = ["ggml_", "[parakeet]", "main:"]
                for prefix in prefixes where trimmed.hasPrefix(prefix) {
                    if let brace = trimmed.firstIndex(of: "{") {
                        trimmed = String(trimmed[brace...])
                    } else {
                        trimmed = ""
                    }
                    break
                }
                return trimmed
            }
            .filter { !$0.isEmpty }
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    /// parakeet-cli 0.4 can return decoder tokens (`id`, `t`, `conf`) in the
    /// `words` field. Keep the transcript usable in that case, but omit timed
    /// formatting until the CLI supplies rendered word records (`w`, `start`,
    /// `end`, `conf`).
    private static func decodeTranscriptionResponse(from data: Data) throws -> TranscriptionResponse {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let response = object as? [String: Any],
              let text = response["text"] as? String else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Expected a transcription object with a text field."
            ))
        }

        let frameSec = (response["frame_sec"] as? NSNumber)?.doubleValue
        let words: [TimedWord]
        if let rawWords = response["words"],
           JSONSerialization.isValidJSONObject(rawWords),
           let wordsData = try? JSONSerialization.data(withJSONObject: rawWords) {
            words = (try? JSONDecoder().decode([TimedWord].self, from: wordsData)) ?? []
        } else {
            words = []
        }

        return TranscriptionResponse(text: text, frame_sec: frameSec, words: words)
    }

    private static func jsonObjects(in raw: String) -> [String] {
        var objects: [String] = []
        var start: String.Index?
        var depth = 0
        var isInString = false
        var isEscaped = false

        for index in raw.indices {
            let char = raw[index]

            if start == nil {
                if char == "{" {
                    start = index
                    depth = 1
                    isInString = false
                    isEscaped = false
                }
                continue
            }

            if isEscaped {
                isEscaped = false
                continue
            }

            if char == "\\" {
                isEscaped = isInString
                continue
            }

            if char == "\"" {
                isInString.toggle()
                continue
            }

            guard !isInString else { continue }

            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0, let objectStart = start {
                    objects.append(String(raw[objectStart...index]))
                    Self.startOver(
                        start: &start,
                        depth: &depth,
                        isInString: &isInString,
                        isEscaped: &isEscaped
                    )
                }
            }
        }

        return objects
    }

    private static func startOver(
        start: inout String.Index?,
        depth: inout Int,
        isInString: inout Bool,
        isEscaped: inout Bool
    ) {
        start = nil
        depth = 0
        isInString = false
        isEscaped = false
    }
}

enum TranscriberError: LocalizedError {
    case notReady(String)
    case processFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notReady(let msg): return msg
        case .processFailed(let msg): return msg
        case .cancelled: return nil
        }
    }
}

enum TranscriptionPhase: String {
    case idle
    case preparing = "Preparing audio"
    case converting = "Converting audio"
    case transcribing = "Transcribing audio"
    case formatting = "Formatting transcript"
}

struct TranscriptionResult {
    let text: String
    let words: [TimedWord]
    let frameSec: Double
}

struct TimedWord: Codable {
    let w: String
    let start: Double
    let end: Double
    let conf: Double
}

struct TranscriptionResponse: Codable {
    let text: String
    let frame_sec: Double?
    let words: [TimedWord]?
}

enum OutputFormat: String, CaseIterable {
    case plain = "Rich Text"
    case timestamped = "Timestamped"
    case srt = "SRT"
}

extension TranscriptionResult {
    func formatted(as format: OutputFormat, grouping: Double = 0.5) -> String {
        switch format {
        case .plain:
            return text
        case .timestamped:
            let groups = groupWords(words, grouping: grouping)
            var out = ""
            for group in groups {
                out += "[\(fmt(group.first!.start))-\(fmt(group.last!.end))] \(group.map(\.w).joined(separator: " "))\n"
            }
            return out.trimmingCharacters(in: .whitespacesAndNewlines)
        case .srt:
            let groups = groupWords(words, grouping: grouping)
            var out = ""
            for (i, group) in groups.enumerated() {
                out += "\(i + 1)\n"
                out += "\(srtTime(group.first!.start)) --> \(srtTime(group.last!.end))\n"
                out += "\(group.map(\.w).joined(separator: " "))\n\n"
            }
            return out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func groupWords(_ words: [TimedWord], grouping: Double) -> [[TimedWord]] {
        let maxGap = 0.1 + grouping * 2.9
        let maxWords = max(1, Int(1 + grouping * 29))

        var groups: [[TimedWord]] = []
        var current: [TimedWord] = []

        for word in words {
            if let last = current.last {
                let gap = word.start - last.end
                if gap > maxGap || current.count >= maxWords {
                    groups.append(current)
                    current = [word]
                } else {
                    current.append(word)
                }
            } else {
                current.append(word)
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    private func fmt(_ t: Double) -> String {
        String(format: "%.2f", t)
    }

    private func srtTime(_ t: Double) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        let ms = Int((t - Double(Int(t))) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }
}
