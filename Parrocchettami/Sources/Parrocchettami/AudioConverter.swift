import AVFoundation

func convertAudioTo16kHzMonoWAV(
    sourceURL: URL,
    destinationURL: URL,
    processRunner: ProcessRunner = ProcessRunner()
) async throws {
    try? FileManager.default.removeItem(at: destinationURL)

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

enum AudioConversionError: LocalizedError {
    case afconvertFailed(Int32, String?)
    case cancelled
    case invalidOutput
    case launchFailed(String)

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
            return "Cannot run afconvert: \(message)"
        }
    }
}
