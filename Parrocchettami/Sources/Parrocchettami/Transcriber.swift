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

    func cancel() {
        guard isTranscribing else { return }
        processRunner.cancel()
        isTranscribing = false
        transcriptionPhase = .idle
    }

    func locateCLI() {
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
        let engineVersion = Self.readParakeetVersion(atPath: cliPath!)
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
                    processRunner: processRunner
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
            "--json"
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

    private static func readParakeetVersion(atPath path: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "Unknown"
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let output, !output.isEmpty else { return "Unknown" }
        return output.components(separatedBy: .newlines).first ?? output
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
        let lines = filteredLines(from: raw)
        let jsonCandidates = jsonObjects(in: raw)
            + lines.filter { $0.hasPrefix("{") && $0.hasSuffix("}") }
        let plainLines = lines.filter { !$0.hasPrefix("{") }.joined(separator: "\n")

        let detail = """
        Exit code: \(output.terminationStatus)
        JSON candidates found: \(jsonCandidates.count)
        Other lines: \(plainLines.isEmpty ? "none" : plainLines)
        --- RAW FIRST 500 CHARS ---
        \(String(raw.prefix(500)))
        """

        if output.terminationStatus != 0 {
            throw TranscriberError.processFailed(detail)
        }

        var lastJSONError: Error?
        for jsonObject in deduplicated(jsonCandidates) {
            guard let jsonData = jsonObject.data(using: .utf8) else { continue }
            do {
                let resp = try JSONDecoder().decode(TranscriptionResponse.self, from: jsonData)
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
            }
        }

        if let lastJSONError,
           jsonCandidates.contains(where: { $0.contains("\"text\"") || $0.contains("\"words\"") }) {
            throw TranscriberError.processFailed(
                "JSON parse failed: \(lastJSONError.localizedDescription)\n\(detail)")
        }

        if !plainLines.isEmpty {
            return (
                TranscriptionResult(text: plainLines, words: [], frameSec: 0.08),
                detail
            )
        } else {
            throw TranscriberError.processFailed("No output from transcription.\n\(detail)")
        }
    }

    private static func filteredLines(from raw: String) -> [String] {
        raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                if line.isEmpty { return false }
                if line.hasPrefix("ggml_") { return false }
                if line.hasPrefix("[parakeet]") { return false }
                if line.hasPrefix("main:") { return false }
                return true
            }
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
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
    case plain = "Plain Text"
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
