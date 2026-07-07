import AVFoundation

func convertAudioTo16kHzMonoWAV(
    sourceURL: URL,
    destinationURL: URL,
    processRunner: any ProcessRunning = ProcessRunner(),
    resourceBaseDir: String? = nil,
    allowSystemOpusDecoderFallback: Bool = true
) async throws {
    try? FileManager.default.removeItem(at: destinationURL)

    if sourceURL.pathExtension.lowercased() == "opus" {
        try await convertOpusTo16kHzMonoWAV(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            processRunner: processRunner,
            resourceBaseDir: resourceBaseDir,
            allowSystemFallback: allowSystemOpusDecoderFallback
        )
        return
    }

    try await convertWithAfconvert(
        sourceURL: sourceURL,
        destinationURL: destinationURL,
        processRunner: processRunner
    )
}

private func convertOpusTo16kHzMonoWAV(
    sourceURL: URL,
    destinationURL: URL,
    processRunner: any ProcessRunning,
    resourceBaseDir: String?,
    allowSystemFallback: Bool
) async throws {
    guard let opusdecURL = locateOpusDecoder(
        resourceBaseDir: resourceBaseDir,
        includeSystemFallbacks: allowSystemFallback
    ) else {
        throw AudioConversionError.opusDecoderNotFound
    }

    let decodedURL = destinationURL
        .deletingLastPathComponent()
        .appendingPathComponent("opus-decoded-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: decodedURL) }

    let output: ProcessOutput
    do {
        output = try await processRunner.run(
            executableURL: opusdecURL,
            arguments: [
                "--quiet",
                "--rate", "16000",
                sourceURL.path,
                decodedURL.path
            ]
        )
    } catch ProcessRunnerError.cancelled {
        throw AudioConversionError.cancelled
    } catch {
        throw AudioConversionError.launchFailed(error.localizedDescription)
    }

    guard output.terminationStatus == 0 else {
        let message = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        throw AudioConversionError.opusdecFailed(output.terminationStatus, message)
    }

    try await convertWithAfconvert(
        sourceURL: decodedURL,
        destinationURL: destinationURL,
        processRunner: processRunner
    )
}

private func convertWithAfconvert(
    sourceURL: URL,
    destinationURL: URL,
    processRunner: any ProcessRunning
) async throws {
    let output: ProcessOutput
    do {
        output = try await processRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/afconvert"),
            arguments: [
                "-f", "WAVE",
                "-d", "LEI16@16000",
                "-c", "1",
                sourceURL.path,
                destinationURL.path
            ]
        )
    } catch ProcessRunnerError.cancelled {
        throw AudioConversionError.cancelled
    } catch {
        throw AudioConversionError.launchFailed(error.localizedDescription)
    }

    guard output.terminationStatus == 0 else {
        let message = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        throw AudioConversionError.afconvertFailed(output.terminationStatus, message)
    }

    guard FileManager.default.fileExists(atPath: destinationURL.path),
          let size = try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
          size > 44 else {
        throw AudioConversionError.invalidOutput
    }
}

func opusDecoderSearchPaths(
    resourceBaseDir: String? = nil,
    includeSystemFallbacks: Bool = true
) -> [String] {
    let base = resourceBaseDir ?? audioResourceBaseDir()
    var bundledPaths = [
        "\(base)/bin/opusdec"
    ]
    if let bundleResourcePath = Bundle.main.resourceURL?.path,
       bundleResourcePath != base {
        bundledPaths.append("\(bundleResourcePath)/bin/opusdec")
    }
    let systemPaths = [
        "/opt/homebrew/bin/opusdec",
        "/usr/local/bin/opusdec",
        "/opt/local/bin/opusdec"
    ]
    return includeSystemFallbacks ? bundledPaths + systemPaths : bundledPaths
}

func locateOpusDecoder(
    resourceBaseDir: String? = nil,
    includeSystemFallbacks: Bool = true
) -> URL? {
    opusDecoderSearchPaths(
        resourceBaseDir: resourceBaseDir,
        includeSystemFallbacks: includeSystemFallbacks
    )
        .first { FileManager.default.isExecutableFile(atPath: $0) }
        .map { URL(fileURLWithPath: $0) }
}

private func audioResourceBaseDir() -> String {
    if let env = ProcessInfo.processInfo.environment["PARROCCHETTAMI_HOME"] {
        return env
    }
    if let resources = Bundle.main.resourceURL?.path {
        return resources
    }
    return FileManager.default.currentDirectoryPath
}

enum AudioConversionError: LocalizedError {
    case afconvertFailed(Int32, String?)
    case cancelled
    case invalidOutput
    case launchFailed(String)
    case opusdecFailed(Int32, String?)
    case opusDecoderNotFound

    var errorDescription: String? {
        switch self {
        case .afconvertFailed(let code, let message):
            let detail = message.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown conversion error"
            return "afconvert failed with exit code \(code): \(detail)"
        case .cancelled:
            return nil
        case .invalidOutput:
            return "Audio conversion produced an empty file"
        case .launchFailed(let message):
            return "Cannot run audio converter: \(message)"
        case .opusdecFailed(let code, let message):
            let detail = message.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown Opus decoding error"
            return "opusdec failed with exit code \(code): \(detail)"
        case .opusDecoderNotFound:
            return "Cannot decode Opus audio because opusdec is not installed or bundled with the app."
        }
    }
}
